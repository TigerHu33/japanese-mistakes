<template>
  <div class="auth-page">
    <el-card class="auth-card">
      <el-tabs v-model="mode">
        <el-tab-pane label="ログイン" name="login" />
        <el-tab-pane label="新規登録" name="signup" />
      </el-tabs>

      <el-form :model="form" label-position="top" @submit.prevent>
        <el-form-item label="ユーザー名 (メールアドレスでも可)">
          <el-input v-model="form.username" autocomplete="username" />
        </el-form-item>
        <el-form-item label="パスワード">
          <el-input v-model="form.password" type="password" autocomplete="current-password" show-password />
        </el-form-item>
        <el-form-item v-if="mode === 'signup'" label="連絡先メールアドレス(任意)">
          <el-input v-model="form.contactEmail" type="email" autocomplete="email" />
        </el-form-item>
        <el-form-item>
          <el-checkbox v-model="form.remember">ログイン状態を保持する</el-checkbox>
        </el-form-item>
      </el-form>

      <el-alert v-if="notice" :title="notice" :type="noticeType" show-icon :closable="false" style="margin-bottom: 12px" />

      <el-button type="primary" :loading="loading" style="width: 100%" @click="submit">
        {{ mode === 'login' ? 'ログイン' : '登録する' }}
      </el-button>
    </el-card>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { signIn, signUp, USERNAME_RE } from '../supabase'

const router = useRouter()
const mode = ref('login')
const loading = ref(false)
const notice = ref('')
const noticeType = ref('info')
const form = reactive({ username: '', password: '', contactEmail: '', remember: true })

async function submit() {
  notice.value = ''
  if (!USERNAME_RE.test(form.username.trim())) {
    noticeType.value = 'error'
    notice.value = 'ユーザー名は英数字・アンダースコア・ハイフンで3〜20文字、またはメールアドレス形式で入力してください'
    return
  }
  loading.value = true
  try {
    if (mode.value === 'login') {
      await signIn(form.username, form.password, form.remember)
      router.push({ name: 'list' })
    } else {
      const { session } = await signUp(form.username, form.password, form.contactEmail, form.remember)
      if (session) {
        router.push({ name: 'list' })
      } else {
        noticeType.value = 'error'
        notice.value = '登録処理は成功しましたがログインできません。Supabase の Authentication → Providers → Email → "Confirm email" を OFF にしてから、もう一度お試しください。'
      }
    }
  } catch (e) {
    noticeType.value = 'error'
    notice.value = e.message || 'エラーが発生しました'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.auth-page {
  display: flex;
  justify-content: center;
  padding-top: 15vh;
}
.auth-card {
  width: 360px;
}
</style>
