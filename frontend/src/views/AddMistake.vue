<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { CATEGORIES, SUB_CATEGORIES, createMistake } from '../api'

const formRef = ref(null)
const form = reactive({
  category: '文字・語彙',
  sub_category: '言い換え類義',
  question: '',
  option1: '',
  option2: '',
  option3: '',
  option4: '',
  correct_option: 1,
  underline_text: '',
  explanation: '',
  source_book: 'JLPT N1 この一冊で合格',
  source_page: ''
})

const subOptions = computed(() => SUB_CATEGORIES[form.category] || [])

watch(() => form.category, (cat) => {
  const list = SUB_CATEGORIES[cat] || []
  if (!list.includes(form.sub_category)) {
    form.sub_category = list[0] || ''
  }
})

const rules = {
  category: [{ required: true, message: '題型を選択してください' }],
  sub_category: [{ required: true, message: '小分類を選択してください' }],
  question: [{ required: true, message: '題目を入力してください' }],
  option1: [{ required: true, message: '選択肢1を入力してください' }],
  option2: [{ required: true, message: '選択肢2を入力してください' }],
  option3: [{ required: true, message: '選択肢3を入力してください' }],
  option4: [{ required: true, message: '選択肢4を入力してください' }],
  correct_option: [{ required: true, message: '正解を選択してください' }]
}

const submit = async () => {
  await formRef.value.validate()
  await createMistake({ ...form })
  ElMessage.success('保存しました')
  Object.assign(form, {
    category: form.category,
    sub_category: form.sub_category,
    question: '',
    option1: '',
    option2: '',
    option3: '',
    option4: '',
    correct_option: 1,
    underline_text: '',
    explanation: '',
    source_book: form.source_book,
    source_page: ''
  })
  formRef.value.clearValidate()
}
</script>

<template>
  <el-card>
    <template #header>錯題録入</template>
    <el-form ref="formRef" :model="form" :rules="rules" label-width="100px">
      <el-form-item label="題型" prop="category">
        <el-select v-model="form.category" style="width: 200px">
          <el-option v-for="c in CATEGORIES" :key="c" :label="c" :value="c" />
        </el-select>
      </el-form-item>
      <el-form-item label="小分類" prop="sub_category">
        <el-select v-model="form.sub_category" style="width: 240px">
          <el-option v-for="s in subOptions" :key="s" :label="s" :value="s" />
        </el-select>
      </el-form-item>
      <el-form-item label="題目" prop="question">
        <el-input v-model="form.question" type="textarea" :rows="3" />
      </el-form-item>
      <el-form-item label="下線部">
        <el-input
          v-model="form.underline_text"
          placeholder="題目中で下線を引きたい語句（例：見合わせる）"
        />
      </el-form-item>
      <el-form-item label="選択肢 1" prop="option1">
        <el-input v-model="form.option1" />
      </el-form-item>
      <el-form-item label="選択肢 2" prop="option2">
        <el-input v-model="form.option2" />
      </el-form-item>
      <el-form-item label="選択肢 3" prop="option3">
        <el-input v-model="form.option3" />
      </el-form-item>
      <el-form-item label="選択肢 4" prop="option4">
        <el-input v-model="form.option4" />
      </el-form-item>
      <el-form-item label="正解" prop="correct_option">
        <el-radio-group v-model="form.correct_option">
          <el-radio :value="1">1</el-radio>
          <el-radio :value="2">2</el-radio>
          <el-radio :value="3">3</el-radio>
          <el-radio :value="4">4</el-radio>
        </el-radio-group>
      </el-form-item>
      <el-form-item label="解説/メモ">
        <el-input v-model="form.explanation" type="textarea" :rows="3" />
      </el-form-item>
      <el-form-item label="教材">
        <el-input
          v-model="form.source_book"
          placeholder="例: JLPT N1 この一冊で合格"
        />
      </el-form-item>
      <el-form-item label="ページ">
        <el-input
          v-model="form.source_page"
          placeholder="例: 78"
          style="width: 160px"
        />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" @click="submit">保存</el-button>
      </el-form-item>
    </el-form>
  </el-card>
</template>

<style scoped>
@media (max-width: 600px) {
  /* ラベルを上に・入力欄を全幅に（label-width 100px だと窮屈なため） */
  :deep(.el-form-item) {
    display: block;
    margin-bottom: 16px;
  }
  :deep(.el-form-item__label) {
    justify-content: flex-start;
    width: auto !important;
    padding: 0 0 4px;
    line-height: 1.4;
  }
  :deep(.el-form-item__content) { margin-left: 0 !important; }
}
</style>
