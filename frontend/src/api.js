import axios from 'axios'

// 有 Supabase 环境变量则走云端 REST;否则回退本地 docker 的 /api(vite proxy)——一套代码两用
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

const http = axios.create({
  baseURL: SUPABASE_URL ? `${SUPABASE_URL}/rest/v1` : '/api',
  headers: {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...(SUPABASE_KEY ? { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } : {})
  }
})

export const CATEGORIES = ['文字・語彙', '文法', '読解']

// JLPT 公式ガイドブック (p.20) の N1 大問名称に準拠
export const SUB_CATEGORIES = {
  '文字・語彙': ['漢字読み', '文脈規定', '言い換え類義', '用法'],
  '文法': ['文の文法1（文法形式の判断）', '文の文法2（文の組み立て）', '文章の文法'],
  '読解': [
    '内容理解（短文）',
    '内容理解（中文）',
    '内容理解（長文）',
    '統合理解',
    '主張理解（長文）',
    '情報検索'
  ]
}

// 1 セッションあたりのデフォルト出題数
export const DEFAULT_COUNTS = {
  '漢字読み': 20,
  '文脈規定': 20,
  '言い換え類義': 20,
  '用法': 20,
  '文の文法1（文法形式の判断）': 20,
  '文の文法2（文の組み立て）': 10,
  '文章の文法': 5,
  '内容理解（短文）': 4,
  '内容理解（中文）': 3,
  '内容理解（長文）': 2,
  '統合理解': 2,
  '主張理解（長文）': 2,
  '情報検索': 4
}
export const DEFAULT_COUNT_FALLBACK = 20

// 小分類ごとの 1 問あたり目安秒数（本番試験の配分に基づく）
export const SECONDS_PER_QUESTION = {
  '漢字読み': 20,
  '文脈規定': 30,
  '言い換え類義': 25,
  '用法': 40,
  '文の文法1（文法形式の判断）': 45,
  '文の文法2（文の組み立て）': 60,
  '文章の文法': 60,
  '内容理解（短文）': 180,
  '内容理解（中文）': 240,
  '内容理解（長文）': 480,
  '統合理解': 300,
  '主張理解（長文）': 480,
  '情報検索': 180
}
export const SECONDS_PER_QUESTION_FALLBACK = 30

export async function listMistakes({ category, sub_category } = {}) {
  const params = { order: 'error_count.desc,last_wrong_at.desc' }
  if (category) params.category = `eq.${category}`
  if (sub_category) params.sub_category = `eq.${sub_category}`
  const { data } = await http.get('/mistakes', { params })
  return data
}

export async function createMistake(payload) {
  const { data } = await http.post('/mistakes', payload, {
    headers: { Prefer: 'return=representation' }
  })
  return data[0]
}

export async function deleteMistake(id) {
  await http.delete(`/mistakes?id=eq.${id}`)
}

export async function updateMistake(id, payload) {
  const { data } = await http.patch(`/mistakes?id=eq.${id}`, payload, {
    headers: { Prefer: 'return=representation' }
  })
  return data[0]
}

// 调用 PostgreSQL 函数：原子性地 error_count + 1
export async function incrementError(id) {
  const { data } = await http.post('/rpc/increment_error', { mistake_id: id })
  return data
}

// 練習プール取得：
//   「未演習(没做过)」と「間違いが多い(错最多)」を 3:1 の比率で混ぜる。
//   例) 20 問 → 未演習 15 + 間違い多い 5。
//   2 つのバケツは last_practiced_at の NULL / NOT NULL で排他なので重複しない。
//   片方が不足した場合はもう片方で補充し、必ず total 件に揃える。
export async function getPracticePool({ category, sub_category, limit }) {
  const total = limit || DEFAULT_COUNT_FALLBACK
  const errorTarget = Math.round(total / 4) // 1/4 = 错最多
  const neverTarget = total - errorTarget   // 3/4 = 没做过

  const base = { category: `eq.${category}` }
  if (sub_category) base.sub_category = `eq.${sub_category}`

  // ① 没做过：last_practiced_at IS NULL（不足時の補充用に total 件まで多めに取得）
  const neverParams = {
    ...base,
    last_practiced_at: 'is.null',
    order: 'error_count.desc,id.asc',
    limit: total
  }
  // ② 错最多：演習済み(IS NOT NULL)を error_count 降順
  const errorParams = {
    ...base,
    last_practiced_at: 'not.is.null',
    order: 'error_count.desc,last_practiced_at.asc',
    limit: total
  }

  const [neverRes, errorRes] = await Promise.all([
    http.get('/mistakes', { params: neverParams }),
    http.get('/mistakes', { params: errorParams })
  ])
  const never = neverRes.data
  const errs = errorRes.data

  const seen = new Set()
  const result = []
  const pushUpTo = (arr, n) => {
    for (const m of arr) {
      if (n <= 0) break
      if (seen.has(m.id)) continue
      seen.add(m.id)
      result.push(m)
      n--
    }
  }
  // 目標比率で各バケツから取得 → 不足分は相互に補充
  pushUpTo(errs, errorTarget)
  pushUpTo(never, neverTarget)
  if (result.length < total) pushUpTo(never, total - result.length)
  if (result.length < total) pushUpTo(errs, total - result.length)
  return result
}

// 解答済み（正解／不正解問わず）として last_practiced_at を更新
export async function markPracticed(id) {
  await http.patch(`/mistakes?id=eq.${id}`, { last_practiced_at: new Date().toISOString() })
}

// ===== 真題模試 =====

// 套題一覧（年度降順）
export async function listPapers() {
  const { data } = await http.get('/papers', { params: { order: 'exam_year.desc,id.desc' } })
  return data
}

// 一套真題の全題目（所属文章を埋め込み、seq 順）
export async function getPaperBundle(paperId) {
  const { data } = await http.get('/paper_questions', {
    params: {
      paper_id: `eq.${paperId}`,
      select: '*,paper_passages(*)',
      order: 'seq.asc'
    }
  })
  return data
}

// 交卷後：間違えた問題を mistakes へ投影。
//   去重は source_book + source_page（＝問題{section}-{seq}、短く一意）で行う。
//   既存なら increment_error、なければ INSERT。読解は文章を題干に前置して独立成立させる。
export async function archiveWrongToMistakes(wrongQuestions, paper) {
  let inserted = 0
  let incremented = 0
  for (const q of wrongQuestions) {
    const sourcePage = `問題${q.section}-${q.seq}`
    const { data: hit } = await http.get('/mistakes', {
      params: {
        source_book: `eq.${paper.source_book}`,
        source_page: `eq.${sourcePage}`,
        select: 'id',
        limit: 1
      }
    })
    if (hit.length) {
      await http.post('/rpc/increment_error', { mistake_id: hit[0].id })
      incremented++
      continue
    }
    const passage = q.paper_passages
    let question = q.question
    if (passage && passage.body) {
      const body = passage.body_b
        ? `${passage.body}\n\n【B】\n${passage.body_b}`
        : passage.body
      question = `${body}\n\n【設問】${q.question}`
    }
    await http.post(
      '/mistakes',
      [{
        category: q.category,
        sub_category: q.sub_category,
        question,
        option1: q.option1,
        option2: q.option2,
        option3: q.option3,
        option4: q.option4,
        correct_option: q.correct_option,
        blanks: q.blanks ?? null,
        option_underlines: q.option_underlines ?? null,
        underline_text: q.underline_text ?? null,
        explanation: q.explanation ?? null,
        source_book: paper.source_book,
        source_page: sourcePage
      }],
      { headers: { Prefer: 'return=representation' } }
    )
    inserted++
  }
  return { inserted, incremented }
}
