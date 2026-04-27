<script setup>
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { CATEGORIES, SUB_CATEGORIES, listMistakes, incrementError } from '../api'

const category = ref('文字・語彙')
const subCategory = ref('')
const subOptions = computed(() => SUB_CATEGORIES[category.value] || [])

watch(category, () => { subCategory.value = '' })

const pool = ref([])
const current = ref(null)
const selected = ref(null)
const submitted = ref(false)
const isCorrect = ref(false)
const stats = ref({ done: 0, correct: 0 })
const loading = ref(false)

const start = async () => {
  loading.value = true
  try {
    pool.value = await listMistakes({
      category: category.value,
      sub_category: subCategory.value || undefined
    })
    if (pool.value.length === 0) {
      ElMessage.warning('この題型の錯題がありません')
      current.value = null
      return
    }
    stats.value = { done: 0, correct: 0 }
    nextQuestion()
  } finally {
    loading.value = false
  }
}

const nextQuestion = () => {
  selected.value = null
  submitted.value = false
  isCorrect.value = false
  if (pool.value.length === 0) {
    current.value = null
    ElMessage.success('全問完了しました')
    return
  }
  const idx = Math.floor(Math.random() * pool.value.length)
  current.value = pool.value.splice(idx, 1)[0]
}

const submit = async () => {
  if (selected.value == null) {
    ElMessage.warning('選択肢を選んでください')
    return
  }
  submitted.value = true
  isCorrect.value = selected.value === current.value.correct_option
  stats.value.done += 1
  if (isCorrect.value) {
    stats.value.correct += 1
  } else {
    await incrementError(current.value.id)
  }
}

const options = computed(() => {
  if (!current.value) return []
  return [1, 2, 3, 4].map((n) => ({ n, text: current.value[`option${n}`] }))
})

const renderQuestion = (m) => {
  if (!m.underline_text) return escapeHtml(m.question)
  const safeQ = escapeHtml(m.question)
  const safeWord = escapeHtml(m.underline_text)
  const escaped = safeWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return safeQ.replace(new RegExp(escaped), `<u class="underline-word">${safeWord}</u>`)
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}
</script>

<template>
  <el-card v-loading="loading">
    <template #header>練習モード</template>

    <div v-if="!current" class="setup">
      <el-form inline>
        <el-form-item label="題型">
          <el-select v-model="category" style="width: 180px">
            <el-option v-for="c in CATEGORIES" :key="c" :label="c" :value="c" />
          </el-select>
        </el-form-item>
        <el-form-item label="小分類">
          <el-select
            v-model="subCategory"
            placeholder="（指定なし）"
            clearable
            style="width: 220px"
          >
            <el-option v-for="s in subOptions" :key="s" :label="s" :value="s" />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="start">開始</el-button>
        </el-form-item>
      </el-form>
      <div v-if="stats.done > 0" class="summary">
        前回：{{ stats.done }} 問中 {{ stats.correct }} 問正解
      </div>
    </div>

    <div v-else class="quiz">
      <div class="meta">
        残り {{ pool.length }} 問 / 正解 {{ stats.correct }}・回答 {{ stats.done }}
      </div>
      <h3 class="question" v-html="renderQuestion(current)"></h3>
      <el-radio-group v-model="selected" :disabled="submitted" class="options">
        <el-radio
          v-for="opt in options"
          :key="opt.n"
          :value="opt.n"
          :class="{
            'correct': submitted && opt.n === current.correct_option,
            'wrong': submitted && opt.n === selected && selected !== current.correct_option
          }"
        >
          {{ opt.n }}. {{ opt.text }}
        </el-radio>
      </el-radio-group>

      <div v-if="submitted" class="feedback">
        <el-alert
          :type="isCorrect ? 'success' : 'error'"
          :title="isCorrect ? '正解' : '不正解（間違い回数 +1）'"
          :closable="false"
        />
        <div v-if="current.explanation" class="explanation">
          <strong>解説：</strong>{{ current.explanation }}
        </div>
      </div>

      <div class="actions">
        <el-button v-if="!submitted" type="primary" @click="submit">回答する</el-button>
        <el-button v-else type="primary" @click="nextQuestion">次の問題</el-button>
      </div>
    </div>
  </el-card>
</template>

<style scoped>
.setup, .quiz { padding: 8px 0; }
.summary { margin-top: 12px; color: #909399; }
.meta { color: #909399; margin-bottom: 12px; }
.question { white-space: pre-wrap; line-height: 1.6; }
.options { display: flex; flex-direction: column; gap: 8px; margin: 16px 0; align-items: stretch; }
.options :deep(.el-radio) {
  display: flex;
  align-items: center;
  width: 100%;
  margin-right: 0;
  padding: 10px 12px;
  border-radius: 4px;
  height: auto;
}
.options :deep(.el-radio__label) {
  flex: 1;
  white-space: normal;
  text-align: left;
  font-size: 15px;
}
.options :deep(.el-radio.correct) { background: #f0f9eb; }
.options :deep(.el-radio.wrong) { background: #fef0f0; }
.question :deep(.underline-word) {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 4px;
  font-weight: 600;
}
.feedback { margin: 16px 0; }
.explanation { margin-top: 12px; padding: 12px; background: #f5f7fa; border-radius: 4px; }
.actions { margin-top: 16px; }
</style>
