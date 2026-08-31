import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import App from './App.vue'
import AddMistake from './views/AddMistake.vue'
import MistakeList from './views/MistakeList.vue'
import Practice from './views/Practice.vue'
import MockExam from './views/MockExam.vue'
import Auth from './views/Auth.vue'
import { supabase, getSession } from './supabase'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', redirect: '/list' },
    { path: '/login', component: Auth, name: 'login', meta: { title: 'ログイン' } },
    { path: '/list', component: MistakeList, name: 'list', meta: { title: '錯題一覧' } },
    { path: '/add', component: AddMistake, name: 'add', meta: { title: '錯題録入' } },
    { path: '/practice', component: Practice, name: 'practice', meta: { title: '練習モード' } },
    { path: '/mock', component: MockExam, name: 'mock', meta: { title: '真題模試' } },
    // 未知パスはログイン画面へ(ログイン済みかどうかは問わない)
    { path: '/:pathMatch(.*)*', redirect: '/login' }
  ]
})

// ローカル docker モード(supabase 未設定)ではログイン機構自体を素通りさせる
router.beforeEach(async (to) => {
  if (!supabase) return true
  if (to.name === 'login') return true
  const session = await getSession()
  if (!session) return { name: 'login' }
  return true
})

createApp(App).use(router).use(ElementPlus).mount('#app')
