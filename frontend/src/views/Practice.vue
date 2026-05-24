<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import {
  CATEGORIES,
  SUB_CATEGORIES,
  DEFAULT_COUNTS,
  DEFAULT_COUNT_FALLBACK,
  SECONDS_PER_QUESTION,
  SECONDS_PER_QUESTION_FALLBACK,
  getPracticePool,
  incrementError,
  markPracticed
} from '../api'

// stage: 'setup' | 'practicing' | 'finished'
const stage = ref('setup')
const loading = ref(false)

const category = ref('文字・語彙')
const subOptions = computed(() => SUB_CATEGORIES[category.value] || [])
const subCategory = ref(subOptions.value[0] || '')
watch(category, () => { subCategory.value = subOptions.value[0] || '' })

const plannedCount = computed(() =>
  subCategory.value
    ? DEFAULT_COUNTS[subCategory.value] || DEFAULT_COUNT_FALLBACK
    : DEFAULT_COUNT_FALLBACK
)

const secondsPerQuestion = computed(() =>
  subCategory.value
    ? SECONDS_PER_QUESTION[subCategory.value] || SECONDS_PER_QUESTION_FALLBACK
    : SECONDS_PER_QUESTION_FALLBACK
)
const plannedSeconds = computed(() => secondsPerQuestion.value * plannedCount.value)

const formatDuration = (sec) => {
  const sign = sec < 0 ? '-' : ''
  const abs = Math.abs(sec)
  const m = Math.floor(abs / 60)
  const s = abs % 60
  return `${sign}${m}:${String(s).padStart(2, '0')}`
}

// セッションタイマー（B 方式：セット全体で 1 つ。残り時間が負になっても続行）
const remainingSeconds = ref(0)
const totalSeconds = ref(0)
let timerId = null
const timerExpired = computed(() => remainingSeconds.value <= 0 && totalSeconds.value > 0)
const remainingLabel = computed(() => formatDuration(remainingSeconds.value))

const stopTimer = () => {
  if (timerId != null) {
    clearInterval(timerId)
    timerId = null
  }
}
const startTimer = (sec) => {
  stopTimer()
  totalSeconds.value = sec
  remainingSeconds.value = sec
  timerId = setInterval(() => {
    remainingSeconds.value -= 1
  }, 1000)
}
onBeforeUnmount(stopTimer)

// セッション内ステート
const queue = ref([])              // これから解く問題
const totalAsked = ref(0)          // 出題数（最初に決まる）
const wrongList = ref([])          // 間違えた問題（再演習用）
const correctList = ref([])        // 正解した問題

const current = ref(null)
const selected = ref(null)
const submitted = ref(false)
const isCorrect = ref(false)

// クローズ題（複数空欄）用ステート
const clozeAnswers = ref({})       // {41: 3, 42: 4, ...}
const isCloze = computed(() => Array.isArray(current.value?.blanks) && current.value.blanks.length > 0)
const clozeAllAnswered = computed(() =>
  isCloze.value && current.value.blanks.every((b) => clozeAnswers.value[b.n] != null)
)
const clozeResults = computed(() => {
  if (!isCloze.value || !submitted.value) return []
  return current.value.blanks.map((b) => ({
    ...b,
    selected: clozeAnswers.value[b.n],
    isCorrect: clozeAnswers.value[b.n] === b.correct
  }))
})

const reviewMode = ref(false)      // 「間違いを見直す」中

// 過去回答した問題のスナップショット（前の問題ボタン用）
const history = ref([])            // [{question, submitted, selected, isCorrect, clozeAnswers}, ...]

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
    history.value = []
    reviewMode.value = false
    stage.value = 'practicing'
    startTimer(secondsPerQuestion.value * queue.value.length)
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
  history.value = []
  reviewMode.value = true
  stage.value = 'practicing'
  startTimer(secondsPerQuestion.value * queue.value.length)
  nextQuestion()
}

const snapshotCurrent = () => ({
  question: current.value,
  submitted: submitted.value,
  isCorrect: isCorrect.value,
  selected: selected.value,
  clozeAnswers: { ...clozeAnswers.value }
})

const nextQuestion = () => {
  // 解答済みの現在問題は履歴に積む
  if (current.value && submitted.value) {
    history.value.push(snapshotCurrent())
  }
  selected.value = null
  submitted.value = false
  isCorrect.value = false
  clozeAnswers.value = {}
  if (queue.value.length === 0) {
    stage.value = 'finished'
    current.value = null
    stopTimer()
    return
  }
  current.value = queue.value.shift()
}

const prevQuestion = () => {
  if (history.value.length === 0) return
  // 現在問題を queue の先頭に戻す（未解答状態は破棄される）
  if (current.value) {
    queue.value.unshift(current.value)
  }
  const prev = history.value.pop()
  current.value = prev.question
  submitted.value = prev.submitted
  isCorrect.value = prev.isCorrect
  selected.value = prev.selected
  clozeAnswers.value = prev.clozeAnswers || {}
}

const submit = async () => {
  if (isCloze.value) {
    if (!clozeAllAnswered.value) {
      ElMessage.warning('すべての空欄に回答してください')
      return
    }
    submitted.value = true
    const allCorrect = current.value.blanks.every((b) => clozeAnswers.value[b.n] === b.correct)
    isCorrect.value = allCorrect
  } else {
    if (selected.value == null) {
      ElMessage.warning('選択肢を選んでください')
      return
    }
    submitted.value = true
    isCorrect.value = selected.value === current.value.correct_option
  }
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
  stopTimer()
}

const options = computed(() => {
  if (!current.value) return []
  return [1, 2, 3, 4].map((n) => ({ n, text: current.value[`option${n}`] }))
})

const renderQuestion = (m) => {
  const safeQ = escapeHtml(m.question)
  if (Array.isArray(m.blanks) && m.blanks.length > 0) {
    return safeQ.replace(/[（(](\d+)[）)]/g, '<span class="blank-marker">($1)</span>')
  }
  if (!m.underline_text) return safeQ
  const safeWord = escapeHtml(m.underline_text)
  const escaped = safeWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return safeQ.replace(new RegExp(escaped), `<u class="underline-word">${safeWord}</u>`)
}

const renderOption = (text, m, idx) => {
  const safe = escapeHtml(text)
  // option_underlines が指定されていればそれを使う（用法に限らず汎用）
  const ul = Array.isArray(m.option_underlines) ? m.option_underlines[idx] : null
  if (ul) {
    const safeWord = escapeHtml(ul)
    const escaped = safeWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    return safe.replace(new RegExp(escaped, 'g'), `<u class="underline-word">${safeWord}</u>`)
  }
  // フォールバック: 用法のときは question を完全一致で下線（旧データ向け）
  if (m.sub_category === '用法' && m.question) {
    const safeWord = escapeHtml(m.question)
    const escaped = safeWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    return safe.replace(new RegExp(escaped, 'g'), `<u class="underline-word">${safeWord}</u>`)
  }
  return safe
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
      <div class="plan">
        出題予定: <strong>{{ plannedCount }}</strong> 問（未演習・古い順を優先）<br />
        制限時間: <strong>{{ formatDuration(plannedSeconds) }}</strong>
        <span class="plan-sub">（{{ secondsPerQuestion }} 秒 / 問）</span>
      </div>
      <el-button type="primary" @click="startSession">開始</el-button>
    </div>

    <!-- 練習中 -->
    <div v-else-if="stage === 'practicing' && current" class="quiz">
      <div class="meta">
        <el-button size="small" plain @click="finishSession">← 戻る</el-button>
        <span v-if="reviewMode" class="review-badge">見直し中</span>
        進捗 {{ progressDone + 1 }} / {{ totalAsked }}
        ・正解 {{ correctList.length }}
        ・不正解 {{ wrongList.length }}
        <span class="timer" :class="{ 'timer-expired': timerExpired }">
          残 {{ remainingLabel }}
          <span v-if="timerExpired" class="timer-warn">時間超過</span>
        </span>
      </div>
      <div class="question" v-html="renderQuestion(current)"></div>

      <!-- 単問 -->
      <el-radio-group
        v-if="!isCloze"
        v-model="selected"
        :disabled="submitted"
        class="options"
      >
        <el-radio
          v-for="opt in options"
          :key="opt.n"
          :value="opt.n"
          :class="{
            'correct': submitted && opt.n === current.correct_option,
            'wrong': submitted && opt.n === selected && selected !== current.correct_option
          }"
        >
          <span v-html="`${opt.n}. ` + renderOption(opt.text, current, opt.n - 1)"></span>
        </el-radio>
      </el-radio-group>

      <!-- クローズ（複数空欄） -->
      <div v-else class="cloze-blanks">
        <div v-for="b in current.blanks" :key="b.n" class="cloze-blank">
          <div class="blank-num">({{ b.n }})</div>
          <el-radio-group
            v-model="clozeAnswers[b.n]"
            :disabled="submitted"
            class="options"
          >
            <el-radio
              v-for="(text, idx) in b.options"
              :key="idx"
              :value="idx + 1"
              :class="{
                'correct': submitted && (idx + 1) === b.correct,
                'wrong': submitted && (idx + 1) === clozeAnswers[b.n] && clozeAnswers[b.n] !== b.correct
              }"
            >{{ idx + 1 }}. {{ text }}</el-radio>
          </el-radio-group>
        </div>
      </div>

      <div v-if="submitted" class="feedback">
        <el-alert
          :type="isCorrect ? 'success' : 'error'"
          :title="isCorrect ? '正解' : '不正解（間違い回数 +1）'"
          :closable="false"
        />
        <!-- クローズ：空欄ごとの解説 -->
        <div v-if="isCloze" class="cloze-explanations">
          <div v-for="r in clozeResults" :key="r.n" class="cloze-exp">
            <div class="cloze-exp-head">
              <span class="blank-num">({{ r.n }})</span>
              <span :class="r.isCorrect ? 'res-ok' : 'res-ng'">
                {{ r.isCorrect ? '○' : '×' }}
                正解 {{ r.correct }}. {{ r.options[r.correct - 1] }}
              </span>
            </div>
            <div v-if="r.explanation" class="explanation">{{ r.explanation }}</div>
          </div>
        </div>
        <div v-else-if="current.explanation" class="explanation">
          <strong>解説：</strong>{{ current.explanation }}
        </div>
      </div>

      <div class="actions">
        <el-button
          v-if="history.length > 0"
          plain
          @click="prevQuestion"
        >← 前の問題</el-button>
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
            <template v-if="Array.isArray(m.blanks) && m.blanks.length > 0">
              <span>クローズ {{ m.source_page }}</span>
              <span class="ans">→ {{ m.blanks.map(b => `(${b.n})${b.correct}`).join(' ') }}</span>
            </template>
            <template v-else>
              <span v-html="renderQuestion(m)"></span>
              <span class="ans">→ {{ m.correct_option }}. {{ m[`option${m.correct_option}`] }}</span>
            </template>
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
.plan { margin: 12px 0; color: #606266; line-height: 1.8; }
.plan-sub { color: #909399; font-size: 13px; margin-left: 4px; }
.timer {
  margin-left: auto;
  padding: 2px 10px;
  border-radius: 3px;
  background: #f0f9eb;
  color: #67c23a;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
}
.timer-expired {
  background: #fef0f0;
  color: #f56c6c;
  animation: timer-pulse 1.2s ease-in-out infinite;
}
.timer-warn { margin-left: 6px; font-size: 12px; }
@keyframes timer-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.6; }
}
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
.cloze-blanks { margin: 16px 0; display: flex; flex-direction: column; gap: 16px; }
.cloze-blank {
  border: 1px solid #ebeef5;
  border-radius: 4px;
  padding: 12px;
  background: #fafbfc;
}
.blank-num {
  display: inline-block;
  font-weight: 600;
  color: #409eff;
  margin-bottom: 6px;
}
.question :deep(.blank-marker) {
  display: inline-block;
  padding: 0 4px;
  background: #ecf5ff;
  color: #409eff;
  border-radius: 3px;
  font-weight: 600;
  margin: 0 2px;
}
.cloze-explanations { margin-top: 12px; display: flex; flex-direction: column; gap: 12px; }
.cloze-exp {
  padding: 10px 12px;
  background: #f5f7fa;
  border-radius: 4px;
}
.cloze-exp-head { display: flex; gap: 8px; align-items: center; margin-bottom: 6px; }
.cloze-exp-head .res-ok { color: #67c23a; font-weight: 500; }
.cloze-exp-head .res-ng { color: #f56c6c; font-weight: 500; }
.cloze-exp .explanation { white-space: pre-wrap; line-height: 1.6; padding: 0; background: transparent; }
.feedback { margin: 16px 0; }
.explanation { margin-top: 12px; padding: 12px; background: #f5f7fa; border-radius: 4px; white-space: pre-wrap; line-height: 1.6; }
.actions { margin-top: 16px; display: flex; gap: 8px; flex-wrap: wrap; }
.question :deep(.underline-word),
.options :deep(.underline-word) {
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
