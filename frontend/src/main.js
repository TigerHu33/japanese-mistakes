import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import App from './App.vue'
import AddMistake from './views/AddMistake.vue'
import MistakeList from './views/MistakeList.vue'
import Practice from './views/Practice.vue'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', redirect: '/list' },
    { path: '/list', component: MistakeList, name: 'list', meta: { title: '錯題一覧' } },
    { path: '/add', component: AddMistake, name: 'add', meta: { title: '錯題録入' } },
    { path: '/practice', component: Practice, name: 'practice', meta: { title: '練習モード' } }
  ]
})

createApp(App).use(router).use(ElementPlus).mount('#app')
