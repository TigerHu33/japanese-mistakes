import axios from 'axios'

const http = axios.create({
  baseURL: '/api',
  headers: {
    'Content-Type': 'application/json',
    Accept: 'application/json'
  }
})

export const CATEGORIES = ['文字・語彙', '文法', '読解']

export const SUB_CATEGORIES = {
  '文字・語彙': ['漢字読み', '文脈規定', '言い換え類義', '用法'],
  '文法': ['文法形式', '文の組み立て', '文章の文法'],
  '読解': ['内容理解(短文)', '内容理解(中文)', '内容理解(長文)', '統合理解', '主張理解', '情報検索']
}

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
