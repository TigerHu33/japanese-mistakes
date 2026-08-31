import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

// 「ログイン状態を保持する」チェックボックスの状態。
// true  = localStorage に保存(ブラウザを閉じても残る。トークンは自動更新され続ける)
// false = sessionStorage に保存(タブ/ブラウザを閉じると消える)。
//         さらに getSession() 側で有効期限切れを自前チェックし、
//         supabase-js の「autoRefreshToken:false でも getSession() が黙って
//         トークンを更新してしまう」既知挙動を迂回して強制ログアウトする。
const REMEMBER_KEY = 'jm-remember-me'

function isRemembered() {
  return localStorage.getItem(REMEMBER_KEY) !== 'false'
}

export function setRememberMe(remember) {
  localStorage.setItem(REMEMBER_KEY, remember ? 'true' : 'false')
}

const hybridStorage = {
  getItem: (key) => localStorage.getItem(key) ?? sessionStorage.getItem(key),
  setItem: (key, value) => {
    if (isRemembered()) {
      localStorage.setItem(key, value)
      sessionStorage.removeItem(key)
    } else {
      // refresh_token を持たせないと SDK が期限切れ間際に黙って更新できなくなり、
      // アクセストークンが自然に切れた時点で本当にログアウト状態になる。
      let toStore = value
      try {
        const parsed = JSON.parse(value)
        if (parsed && typeof parsed === 'object' && 'refresh_token' in parsed) {
          toStore = JSON.stringify({ ...parsed, refresh_token: '' })
        }
      } catch {
        // JSON でなければそのまま保存
      }
      sessionStorage.setItem(key, toStore)
      localStorage.removeItem(key)
    }
  },
  removeItem: (key) => {
    localStorage.removeItem(key)
    sessionStorage.removeItem(key)
  }
}

// 本地 docker(PostgREST)モードでは env が無い。その場合ログイン機能は使わない。
export const supabase = SUPABASE_URL
  ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { storage: hybridStorage } })
  : null

// ログイン識別子は「短いハンドル」でも「メールアドレスそのもの」でもよい。
// @ を含まなければ Supabase Auth 用の内部合成メールに変換する(画面には出さない)。
// @ を含む場合はそのまま Auth の email として使う(=メールをユーザー名として使う運用)。
const AUTH_EMAIL_DOMAIN = 'users.japanese-mistakes.internal'
const HANDLE_RE = /^[a-zA-Z0-9_-]{3,20}$/
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
export const USERNAME_RE = new RegExp(`(?:${HANDLE_RE.source}|${EMAIL_RE.source})`)

function usernameToEmail(username) {
  const v = username.trim().toLowerCase()
  return v.includes('@') ? v : `${v}@${AUTH_EMAIL_DOMAIN}`
}

export async function getSession() {
  if (!supabase) return null
  let session
  try {
    const { data } = await supabase.auth.getSession()
    session = data.session
  } catch {
    // refresh_token が無い状態で期限切れになると SDK は例外を投げる(AuthSessionMissingError)。
    // これは「セッションが無い」ことの表明そのものなので、未ログインとして扱う。
    await supabase.auth.signOut().catch(() => {})
    return null
  }
  if (!session) return null
  // 「保持しない」設定なのに期限切れの場合は、SDK の暗黙リフレッシュを信用せず強制ログアウト。
  if (!isRemembered() && session.expires_at && Date.now() / 1000 >= session.expires_at) {
    await supabase.auth.signOut()
    return null
  }
  return session
}

export async function signIn(username, password, remember = true) {
  setRememberMe(remember)
  const { data, error } = await supabase.auth.signInWithPassword({
    email: usernameToEmail(username),
    password
  })
  if (error) throw error
  return data
}

export async function signUp(username, password, contactEmail, remember = true) {
  setRememberMe(remember)
  const { data, error } = await supabase.auth.signUp({
    email: usernameToEmail(username),
    password,
    options: {
      data: {
        username: username.trim().toLowerCase(),
        contact_email: contactEmail ? contactEmail.trim() : null
      }
    }
  })
  if (error) throw error
  return data
}

export async function signOut() {
  await supabase.auth.signOut()
}
