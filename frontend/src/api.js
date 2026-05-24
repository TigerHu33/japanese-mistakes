import axios from 'axios'

const http = axios.create({
  baseURL: '/api',
  headers: {
    'Content-Type': 'application/json',
    Accept: 'application/json'
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

// 練習プール取得：last_practiced_at が NULL or 古い順を優先
export async function getPracticePool({ category, sub_category, limit }) {
  const params = {
    category: `eq.${category}`,
    order: 'last_practiced_at.asc.nullsfirst,error_count.desc'
  }
  if (sub_category) params.sub_category = `eq.${sub_category}`
  if (limit) params.limit = limit
  const { data } = await http.get('/mistakes', { params })
  return data
}

// 解答済み（正解／不正解問わず）として last_practiced_at を更新
export async function markPracticed(id) {
  await http.patch(`/mistakes?id=eq.${id}`, { last_practiced_at: new Date().toISOString() })
}
