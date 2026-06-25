<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { listPapers, getPaperBundle, archiveWrongToMistakes } from '../api'

// stage: 'setup' | 'exam' | 'result'
const stage = ref('setup')
const loading = ref(false)

const papers = ref([])
const selectedPaperId = ref(null)
const paper = computed(() => papers.value.find((p) => p.id === selectedPaperId.value) || null)

const questions = ref([])     // paper_questions（paper_passages 埋め込み済み、seq 順）
const answers = ref({})       // { [questionId]: number(単問) | {blankN: number}(cloze) }

// 大問ごとの説明文
const INSTRUCTIONS = {
  1: '＿＿の言葉の読み方として最もよいものを、1・2・3・4から一つ選びなさい。',
  2: '（　）に入れるのに最もよいものを、1・2・3・4から一つ選びなさい。',
  3: '＿＿の言葉に意味が最も近いものを、1・2・3・4から一つ選びなさい。',
  4: '次の言葉の使い方として最もよいものを、1・2・3・4から一つ選びなさい。',
  5: '次の文の（　）に入れるのに最もよいものを、1・2・3・4から一つ選びなさい。',
  6: '次の文の ★ に入る最もよいものを、1・2・3・4から一つ選びなさい。',
  7: '次の文章を読んで、文章全体の内容を考えて、（　）に入る最もよいものを、1・2・3・4から一つ選びなさい。',
  8: '次の文章を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。',
  9: '次の文章を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。',
  10: '次の文章を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。',
  11: '次のAとBの文章を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。',
  12: '次の文章を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。',
  13: '右の案内を読んで、後の問いに対する答えとして最もよいものを、1・2・3・4から一つ選びなさい。'
}

const isClozeQ = (q) => Array.isArray(q.blanks) && q.blanks.length > 0

// ===== タイマー =====
const remainingSeconds = ref(0)
let timerId = null
const timerExpired = computed(() => remainingSeconds.value <= 0)
const formatDuration = (sec) => {
  const sign = sec < 0 ? '-' : ''
  const abs = Math.abs(sec)
  const m = Math.floor(abs / 60)
  const s = abs % 60
  return `${sign}${m}:${String(s).padStart(2, '0')}`
}
const stopTimer = () => {
  if (timerId != null) { clearInterval(timerId); timerId = null }
}
const startTimer = (sec) => {
  stopTimer()
  remainingSeconds.value = sec
  timerId = setInterval(() => {
    remainingSeconds.value -= 1
    if (remainingSeconds.value <= 0) {
      stopTimer()
      if (stage.value === 'exam') {
        ElMessage.warning('時間切れです。自動採点します。')
        doGrade()
      }
    }
  }, 1000)
}
onBeforeUnmount(stopTimer)

// ===== 出題構造（大問→ブロック→設問） =====
const examGroups = computed(() => {
  const out = []
  let sec = null
  for (const q of questions.value) {
    if (!sec || sec.section !== q.section) {
      sec = { section: q.section, sub_category: q.sub_category, blocks: [] }
      out.push(sec)
    }
    const pid = q.passage_id ?? null
    let block = sec.blocks[sec.blocks.length - 1]
    if (!block || block.passageId !== pid) {
      block = { passageId: pid, passage: q.paper_passages || null, questions: [] }
      sec.blocks.push(block)
    }
    block.questions.push(q)
  }
  return out
})

// 設問の通し番号（1〜69、cloze はまとめて n〜m）
const qNumbers = computed(() => {
  const map = {}
  let n = 1
  for (const q of questions.value) {
    if (isClozeQ(q)) {
      map[q.id] = `${n}〜${n + q.blanks.length - 1}`
      n += q.blanks.length
    } else {
      map[q.id] = `${n}`
      n += 1
    }
  }
  return map
})

// 解答済み数（cloze は空欄ごと）／総設問数
const totalUnits = computed(() =>
  questions.value.reduce((s, q) => s + (isClozeQ(q) ? q.blanks.length : 1), 0)
)
const answeredUnits = computed(() =>
  questions.value.reduce((s, q) => {
    if (isClozeQ(q)) {
      const a = answers.value[q.id] || {}
      return s + q.blanks.filter((b) => a[b.n] != null).length
    }
    return s + (answers.value[q.id] != null ? 1 : 0)
  }, 0)
)

// ===== 開始 =====
const loadPapers = async () => {
  loading.value = true
  try {
    papers.value = await listPapers()
    if (papers.value.length && selectedPaperId.value == null) {
      selectedPaperId.value = papers.value[0].id
    }
  } finally {
    loading.value = false
  }
}
loadPapers()

const startExam = async () => {
  if (!paper.value) { ElMessage.warning('套題を選んでください'); return }
  loading.value = true
  try {
    const bundle = await getPaperBundle(selectedPaperId.value)
    if (!bundle.length) { ElMessage.warning('この套題には問題がありません'); return }
    questions.value = bundle
    const init = {}
    for (const q of bundle) init[q.id] = isClozeQ(q) ? {} : null
    answers.value = init
    result.value = null
    stage.value = 'exam'
    const minutes = paper.value.total_minutes || 110
    startTimer(minutes * 60)
    window.scrollTo(0, 0)
  } finally {
    loading.value = false
  }
}

// ===== 採点 =====
const result = ref(null)

const doGrade = async () => {
  stopTimer()
  let correct = 0
  const perSection = {}
  const wrong = []
  for (const q of questions.value) {
    const sec = q.section
    if (!perSection[sec]) perSection[sec] = { section: sec, sub: q.sub_category, correct: 0, total: 0 }
    if (isClozeQ(q)) {
      const a = answers.value[q.id] || {}
      const ok = q.blanks.filter((b) => a[b.n] === b.correct).length
      perSection[sec].total += q.blanks.length
      perSection[sec].correct += ok
      correct += ok
      if (ok < q.blanks.length) wrong.push(q)
    } else {
      perSection[sec].total += 1
      if (answers.value[q.id] === q.correct_option) {
        perSection[sec].correct += 1
        correct += 1
      } else {
        wrong.push(q)
      }
    }
  }
  result.value = {
    correct,
    total: totalUnits.value,
    perSection: Object.values(perSection).sort((a, b) => a.section - b.section),
    wrong,
    archive: null
  }
  stage.value = 'result'
  window.scrollTo(0, 0)
  // 错题入库
  try {
    result.value.archive = await archiveWrongToMistakes(wrong, paper.value)
  } catch (e) {
    result.value.archive = { error: true }
  }
}

const submitExam = async () => {
  const left = totalUnits.value - answeredUnits.value
  if (remainingSeconds.value > 0 && left > 0) {
    try {
      await ElMessageBox.confirm(`未回答が ${left} 問あります。提出して採点しますか？`, '確認', {
        confirmButtonText: '提出する', cancelButtonText: 'もどる', type: 'warning'
      })
    } catch { return }
  }
  doGrade()
}

const backToSetup = () => {
  stage.value = 'setup'
  questions.value = []
  result.value = null
  stopTimer()
}

// 結果：間違えた設問の正解番号テキスト
const correctText = (q) => {
  if (isClozeQ(q)) return q.blanks.map((b) => `(${b.n})${b.correct}`).join('　')
  return `${q.correct_option}. ${q[`option${q.correct_option}`]}`
}

// ===== レンダリング補助 =====
function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
const renderQuestion = (q) => {
  const safe = escapeHtml(q.question)
  if (isClozeQ(q)) {
    return safe.replace(/[（(](\d+)[）)]/g, '<span class="blank-marker">($1)</span>')
  }
  if (!q.underline_text) return safe
  const w = escapeHtml(q.underline_text)
  const esc = w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return safe.replace(new RegExp(esc), `<u class="underline-word">${w}</u>`)
}
const renderOption = (text, q, idx) => {
  const safe = escapeHtml(text)
  const ul = Array.isArray(q.option_underlines) ? q.option_underlines[idx] : null
  if (ul) {
    const w = escapeHtml(ul)
    const esc = w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    return safe.replace(new RegExp(esc, 'g'), `<u class="underline-word">${w}</u>`)
  }
  return safe
}
const passageHtml = (p) => {
  if (!p) return ''
  let t = p.body || ''
  if (p.body_b) t = `【A】\n${t}\n\n【B】\n${p.body_b}`
  if (p.title) t = `${p.title}\n\n${t}`
  return escapeHtml(t)
}
</script>

<template>
  <el-card v-loading="loading">
    <template #header>真題模試</template>

    <!-- セットアップ -->
    <div v-if="stage === 'setup'" class="setup">
      <el-form inline>
        <el-form-item label="套題">
          <el-select v-model="selectedPaperId" style="width: 320px" placeholder="套題を選択">
            <el-option v-for="p in papers" :key="p.id" :label="p.name" :value="p.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <div v-if="paper" class="plan">
        制限時間: <strong>{{ paper.total_minutes || 110 }}</strong> 分（言語知識・読解）<br />
        本番形式：分野ごとに通しで解答し、提出後にまとめて採点します。<br />
        <span class="plan-sub">途中で正誤は表示されません。間違えた問題は自動で錯題記録に追加されます。</span>
      </div>
      <el-empty v-if="!loading && papers.length === 0" description="套題がまだありません" />
      <el-button type="primary" :disabled="!paper" @click="startExam">開始</el-button>
    </div>

    <!-- 試験中 -->
    <div v-else-if="stage === 'exam'" class="exam">
      <div class="exam-bar">
        <span class="progress">解答 {{ answeredUnits }} / {{ totalUnits }}</span>
        <span class="timer" :class="{ 'timer-expired': timerExpired }">
          残 {{ formatDuration(remainingSeconds) }}
        </span>
        <el-button type="primary" size="small" @click="submitExam">提出して採点</el-button>
      </div>

      <div v-for="sec in examGroups" :key="sec.section" class="section">
        <div class="section-head">
          <span class="section-title">問題{{ sec.section }}</span>
          <span class="section-instr">{{ INSTRUCTIONS[sec.section] }}</span>
        </div>

        <div v-for="(block, bi) in sec.blocks" :key="bi" class="block">
          <div v-if="block.passage" class="passage">
            <pre class="passage-body">{{ block.passage.body_b
              ? 'A\n' + block.passage.body + '\n\nB\n' + block.passage.body_b
              : (block.passage.title ? block.passage.title + '\n\n' : '') + block.passage.body }}</pre>
          </div>

          <div v-for="q in block.questions" :key="q.id" class="q">
            <div class="q-head">
              <span class="q-no">{{ qNumbers[q.id] }}</span>
              <span class="q-text" v-html="renderQuestion(q)"></span>
            </div>

            <!-- 単問 -->
            <el-radio-group
              v-if="!isClozeQ(q)"
              v-model="answers[q.id]"
              class="options"
            >
              <el-radio v-for="n in 4" :key="n" :value="n">
                <span v-html="`${n}. ` + renderOption(q[`option${n}`], q, n - 1)"></span>
              </el-radio>
            </el-radio-group>

            <!-- クローズ（問題7） -->
            <div v-else class="cloze-blanks">
              <div v-for="b in q.blanks" :key="b.n" class="cloze-blank">
                <div class="blank-num">（{{ b.n }}）</div>
                <el-radio-group v-model="answers[q.id][b.n]" class="options">
                  <el-radio v-for="(text, idx) in b.options" :key="idx" :value="idx + 1">
                    {{ idx + 1 }}. {{ text }}
                  </el-radio>
                </el-radio-group>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="exam-foot">
        <el-button @click="backToSetup">中止</el-button>
        <el-button type="primary" @click="submitExam">提出して採点</el-button>
      </div>
    </div>

    <!-- 結果 -->
    <div v-else-if="stage === 'result' && result" class="result">
      <h3>採点結果 — {{ paper?.name }}</h3>
      <div class="score">
        <span class="score-num">{{ result.correct }}</span> / {{ result.total }} 問正解
      </div>
      <div class="rate">正答率 {{ Math.round((result.correct / result.total) * 100) }}%</div>

      <div v-if="result.archive" class="archive-note">
        <template v-if="result.archive.error">⚠ 錯題記録への追加に失敗しました</template>
        <template v-else>
          錯題記録に追加：新規 {{ result.archive.inserted }} 件 ／ 既存 +1 {{ result.archive.incremented }} 件
        </template>
      </div>

      <h4>分野別正答率</h4>
      <el-table :data="result.perSection" size="small" class="sec-table">
        <el-table-column label="大問" width="80">
          <template #default="{ row }">問題{{ row.section }}</template>
        </el-table-column>
        <el-table-column prop="sub" label="分類" />
        <el-table-column label="正答" width="120">
          <template #default="{ row }">{{ row.correct }} / {{ row.total }}</template>
        </el-table-column>
        <el-table-column label="率" width="80">
          <template #default="{ row }">{{ Math.round((row.correct / row.total) * 100) }}%</template>
        </el-table-column>
      </el-table>

      <div v-if="result.wrong.length > 0" class="wrong-list">
        <h4>間違えた問題（{{ result.wrong.length }}件）</h4>
        <el-collapse>
          <el-collapse-item v-for="q in result.wrong" :key="q.id" :name="q.id">
            <template #title>
              <span class="wrong-title">
                <el-tag size="small" type="info">{{ qNumbers[q.id] }}</el-tag>
                問題{{ q.section }}
                <span class="ans">正解 → {{ correctText(q) }}</span>
              </span>
            </template>
            <div class="wrong-body">
              <div v-if="q.paper_passages" class="passage-mini">
                <pre class="passage-body">{{ q.paper_passages.body_b
                  ? 'A\n' + q.paper_passages.body + '\n\nB\n' + q.paper_passages.body_b
                  : q.paper_passages.body }}</pre>
              </div>
              <div class="q-text" v-html="renderQuestion(q)"></div>
              <div v-if="!isClozeQ(q)" class="opt-list">
                <div v-for="n in 4" :key="n" :class="{ 'opt-correct': n === q.correct_option }">
                  {{ n }}. <span v-html="renderOption(q[`option${n}`], q, n - 1)"></span>
                </div>
              </div>
              <div v-if="q.explanation" class="explanation"><strong>解説：</strong>{{ q.explanation }}</div>
            </div>
          </el-collapse-item>
        </el-collapse>
      </div>

      <div class="actions">
        <el-button @click="backToSetup">套題選択へ</el-button>
        <el-button type="primary" @click="startExam">もう一度</el-button>
        <el-button type="success" @click="$router.push({ name: 'list' })">錯題一覧へ</el-button>
      </div>
    </div>
  </el-card>
</template>

<style scoped>
.setup, .result { padding: 8px 0; }
.plan { margin: 12px 0; color: #606266; line-height: 1.8; }
.plan-sub { color: #909399; font-size: 13px; }

/* 試験中 */
.exam-bar {
  position: sticky;
  top: 0;
  z-index: 10;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  margin: -4px 0 16px;
  background: #fff;
  border-bottom: 1px solid #e4e7ed;
}
.exam-bar .progress { color: #909399; font-size: 14px; }
.timer {
  margin-left: auto;
  padding: 2px 10px;
  border-radius: 3px;
  background: #f0f9eb;
  color: #67c23a;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
}
.timer-expired { background: #fef0f0; color: #f56c6c; }
.section { margin-bottom: 28px; }
.section-head {
  border-left: 4px solid #409eff;
  padding: 4px 10px;
  margin-bottom: 12px;
  background: #ecf5ff;
}
.section-title { font-weight: 600; margin-right: 10px; }
.section-instr { color: #606266; font-size: 13px; }
.block { margin-bottom: 18px; }
.passage {
  border: 1px solid #ebeef5;
  background: #fafbfc;
  border-radius: 4px;
  padding: 12px 14px;
  margin-bottom: 12px;
}
.passage-body {
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
  font-family: inherit;
  font-size: 15px;
  line-height: 1.8;
}
.q { padding: 8px 0 12px; border-bottom: 1px dashed #ebeef5; }
.q-head { display: flex; gap: 8px; line-height: 1.7; }
.q-no {
  flex: none;
  min-width: 28px;
  height: 22px;
  padding: 0 6px;
  border-radius: 3px;
  background: #f0f2f5;
  color: #606266;
  font-size: 13px;
  font-weight: 600;
  text-align: center;
  line-height: 22px;
}
.q-text { white-space: pre-wrap; }
.options { display: flex; flex-direction: column; gap: 6px; margin: 10px 0 4px; align-items: stretch; }
.options :deep(.el-radio) {
  display: flex;
  align-items: center;
  width: 100%;
  margin-right: 0;
  padding: 8px 12px;
  border-radius: 4px;
  height: auto;
}
.options :deep(.el-radio__label) { flex: 1; white-space: normal; text-align: left; font-size: 15px; }
.cloze-blanks { margin: 10px 0; display: flex; flex-direction: column; gap: 14px; }
.cloze-blank { border: 1px solid #ebeef5; border-radius: 4px; padding: 12px; background: #fafbfc; }
.blank-num { display: inline-block; font-weight: 600; color: #409eff; margin-bottom: 6px; }
.q-text :deep(.blank-marker) {
  display: inline-block;
  padding: 0 4px;
  background: #ecf5ff;
  color: #409eff;
  border-radius: 3px;
  font-weight: 600;
  margin: 0 2px;
}
.q-text :deep(.underline-word),
.opt-list :deep(.underline-word) {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 4px;
  font-weight: 600;
}
.exam-foot { display: flex; gap: 8px; justify-content: center; margin-top: 12px; }

/* 結果 */
.result h3 { margin: 0 0 16px; }
.score { font-size: 18px; }
.score-num { font-size: 32px; font-weight: 600; color: #409eff; }
.rate { color: #909399; margin-top: 4px; }
.archive-note {
  margin: 12px 0;
  padding: 8px 12px;
  background: #f0f9eb;
  color: #67c23a;
  border-radius: 4px;
  font-size: 14px;
}
.sec-table { margin: 8px 0 20px; }
.wrong-list { margin-top: 16px; }
.wrong-list h4 { color: #f56c6c; }
.wrong-title { display: inline-flex; gap: 8px; align-items: center; }
.wrong-title .ans { color: #67c23a; }
.wrong-body { padding: 4px 0; }
.passage-mini { background: #fafbfc; border: 1px solid #ebeef5; border-radius: 4px; padding: 10px; margin-bottom: 8px; max-height: 220px; overflow: auto; }
.opt-list { margin: 8px 0; line-height: 1.9; }
.opt-list .opt-correct { color: #67c23a; font-weight: 600; }
.explanation { margin-top: 8px; padding: 10px 12px; background: #f5f7fa; border-radius: 4px; white-space: pre-wrap; line-height: 1.6; }
.actions { margin-top: 20px; display: flex; gap: 8px; flex-wrap: wrap; }

@media (max-width: 600px) {
  .exam-bar { flex-wrap: wrap; gap: 8px; }
  .timer { margin-left: 0; }
  .options :deep(.el-radio__label) { font-size: 14px; }
  .passage-body { font-size: 14px; }
  .actions .el-button { flex: 1; margin-left: 0; }
}
</style>
