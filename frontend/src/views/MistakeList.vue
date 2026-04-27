<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { CATEGORIES, SUB_CATEGORIES, listMistakes, deleteMistake } from '../api'

const filterCategory = ref('')
const filterSub = ref('')
const items = ref([])
const loading = ref(false)

const subOptions = computed(() =>
  filterCategory.value ? SUB_CATEGORIES[filterCategory.value] || [] : []
)

const load = async () => {
  loading.value = true
  try {
    items.value = await listMistakes({
      category: filterCategory.value || undefined,
      sub_category: filterSub.value || undefined
    })
  } finally {
    loading.value = false
  }
}

const remove = async (row) => {
  await ElMessageBox.confirm(`削除しますか？ (id: ${row.id})`, '確認', { type: 'warning' })
  await deleteMistake(row.id)
  ElMessage.success('削除しました')
  await load()
}

const correctText = (row) => {
  return `${row.correct_option}. ${row[`option${row.correct_option}`]}`
}

watch(filterCategory, () => {
  filterSub.value = ''
  load()
})
watch(filterSub, load)
onMounted(load)
</script>

<template>
  <el-card v-loading="loading">
    <template #header>
      <div class="header-row">
        <span>錯題一覧（{{ items.length }}件）</span>
        <div class="filters">
          <el-select
            v-model="filterCategory"
            placeholder="全題型"
            clearable
            style="width: 160px"
          >
            <el-option v-for="c in CATEGORIES" :key="c" :label="c" :value="c" />
          </el-select>
          <el-select
            v-model="filterSub"
            placeholder="小分類"
            clearable
            :disabled="!filterCategory"
            style="width: 200px"
          >
            <el-option v-for="s in subOptions" :key="s" :label="s" :value="s" />
          </el-select>
        </div>
      </div>
    </template>

    <el-table :data="items" stripe>
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column prop="category" label="題型" width="110" />
      <el-table-column prop="sub_category" label="小分類" width="140">
        <template #default="{ row }">{{ row.sub_category || '-' }}</template>
      </el-table-column>
      <el-table-column prop="question" label="題目" show-overflow-tooltip />
      <el-table-column label="正解" width="200">
        <template #default="{ row }">{{ correctText(row) }}</template>
      </el-table-column>
      <el-table-column prop="error_count" label="間違い" width="80" sortable />
      <el-table-column label="操作" width="100">
        <template #default="{ row }">
          <el-button size="small" type="danger" @click="remove(row)">削除</el-button>
        </template>
      </el-table-column>
    </el-table>
  </el-card>
</template>

<style scoped>
.header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.filters { display: flex; gap: 8px; }
</style>
