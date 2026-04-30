<script setup>
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import {
  CATEGORIES,
  SUB_CATEGORIES,
  DEFAULT_COUNTS,
  DEFAULT_COUNT_FALLBACK,
  getPracticePool,
  incrementError,
  markPracticed
} from '../api'

// stage: 'setup' | 'practicing' | 'finished'
const stage = ref('setup')
const loading = ref(false)

const category = ref('文字・語彙')
const subCategory = ref('')
const subOptions = computed(() => SUB_CATEGORIES[category.value] || [])
watch(category, () => { subCategory.value = '' })

const plannedCount = computed(() =>
  subCategory.value
    ? DEFAULT_COUNTS[subCategory.value] || DEFAULT_COUNT_FALLBACK
    : DEFAULT_COUNT_FALLBACK
)

// セッション内ステート
const queue = ref([])              // これから解く問題
const totalAsked = ref(0)          // 出題数（最初に決まる）
const wrongList = ref([])          // 間違えた問題（再演習用）
const correctList = ref([])        // 正解した問題

const current = ref(null)
const selected = ref(null)
const submitted = ref(false)
const isCorrect = ref(false)

const reviewMode = ref(false)      // 「間違いを見直す」中

const shuffle = (arr) => {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

const startSession = async () => {
  loading.value = true
  try {
    const pool = await getPracticePool({
      category: category.value,
      sub_category: subCategory.value || undefined,
      limit: plannedCount.value
    })
    if (pool.length === 0) {
      ElMessage.warning('該当する錯題がありません')
      return
    }
    queue.value = shuffle(pool)
    totalAsked.value = queue.value.length
    wrongList.value = []
    correctList.value = []
    reviewMode.value = false
    stage.value = 'practicing'
    nextQuestion()
  } finally {
    loading.value = false
  }
}

const startReviewWrong = () => {
  if (wrongList.value.length === 0) return
  queue.value = shuffle(wrongList.value)
  totalAsked.value = queue.value.length
  wrongList.value = []
  correctList.value = []
  reviewMode.value = true
  stage.value = 'practicing'
  nextQuestion()
}

const nextQuestion = () => {
  selected.value = null
  submitted.value = false
  isCorrect.value = false
  if (queue.value.length === 0) {
    stage.value = 'finished'
    current.value = null
    return
  }
  current.value = queue.value.shift()
}

const submit = async () => {
  if (selected.value == null) {
    ElMessage.warning('選択肢を選んでください')
    return
  }
  submitted.value = true
  isCorrect.value = selected.value === current.value.correct_option
  if (isCorrect.value) {
    correctList.value.push(current.value)
  } else {
    wrongList.value.push(current.value)
    await incrementError(current.value.id)
  }
  await markPracticed(current.value.id)
}

const finishSession = () => {
  stage.value = 'setup'
  current.value = null
  queue.value = []
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

const progressDone = computed(() => totalAsked.value - queue.value.length - (current.value ? 1 : 0))
</script>

<template>
  <el-card v-loading="loading">
    <template #header>練習モード</template>

    <!-- セットアップ -->
    <div v-if="stage === 'setup'" class="setup">
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
            style="width: 260px"
          >
            <el-option v-for="s in subOptions" :key="s" :label="s" :value="s" />
          </el-select>
        </el-form-item>
      </el-form>
      <div class="plan">出題予定: <strong>{{ plannedCount }}</strong> 問（未演習・古い順を優先）</div>
      <el-button type="primary" @click="startSession">開始</el-button>
    </div>

    <!-- 練習中 -->
    <div v-else-if="stage === 'practicing' && current" class="quiz">
      <div class="meta">
        <span v-if="reviewMode" class="review-badge">見直し中</span>
        進捗 {{ progressDone + 1 }} / {{ totalAsked }}
        ・正解 {{ correctList.length }}
        ・不正解 {{ wrongList.length }}
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

    <!-- 結果画面 -->
    <div v-else-if="stage === 'finished'" class="result">
      <h3>{{ reviewMode ? '見直し終了' : 'セッション終了' }}</h3>
      <div class="score">
        <span class="score-num">{{ correctList.length }}</span>
        / {{ totalAsked }} 問正解
      </div>
      <div class="rate">正答率 {{ Math.round((correctList.length / totalAsked) * 100) }}%</div>

      <div v-if="wrongList.length > 0" class="wrong-list">
        <h4>間違えた問題（{{ wrongList.length }}件）</h4>
        <ul>
          <li v-for="m in wrongList" :key="m.id">
            <span v-html="renderQuestion(m)"></span>
            <span class="ans">→ {{ m.correct_option }}. {{ m[`option${m.correct_option}`] }}</span>
          </li>
        </ul>
      </div>

      <div class="actions">
        <el-button @click="finishSession">完了</el-button>
        <el-button type="primary" @click="startSession">もう一組</el-button>
        <el-button
          type="warning"
          :disabled="wrongList.length === 0"
          @click="startReviewWrong"
        >間違いを見直す（{{ wrongList.length }}）</el-button>
      </div>
    </div>
  </el-card>
</template>

<style scoped>
.setup, .quiz, .result { padding: 8px 0; }
.plan { margin: 12px 0; color: #606266; }
.meta { color: #909399; margin-bottom: 12px; display: flex; gap: 12px; align-items: center; }
.review-badge {
  background: #faecd8;
  color: #e6a23c;
  padding: 2px 8px;
  border-radius: 3px;
  font-size: 12px;
}
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
.feedback { margin: 16px 0; }
.explanation { margin-top: 12px; padding: 12px; background: #f5f7fa; border-radius: 4px; }
.actions { margin-top: 16px; display: flex; gap: 8px; flex-wrap: wrap; }
.question :deep(.underline-word) {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 4px;
  font-weight: 600;
}

.result h3 { margin: 0 0 16px 0; }
.score { font-size: 18px; }
.score-num { font-size: 32px; font-weight: 600; color: #409eff; }
.rate { color: #909399; margin-top: 4px; }
.wrong-list { margin-top: 24px; }
.wrong-list h4 { color: #f56c6c; }
.wrong-list ul { padding-left: 20px; line-height: 1.8; }
.wrong-list .ans { color: #67c23a; margin-left: 8px; }
</style>
