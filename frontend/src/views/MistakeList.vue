<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { CATEGORIES, SUB_CATEGORIES, listMistakes, deleteMistake } from '../api'

const filterCategory = ref('')
const filterSub = ref('')
const items = ref([])
const loading = ref(false)
const expanded = ref([])

const subOptions = computed(() =>
  filterCategory.value ? SUB_CATEGORIES[filterCategory.value] || [] : []
)

const grouped = computed(() => {
  const byCat = new Map()
  for (const cat of CATEGORIES) byCat.set(cat, new Map())

  for (const it of items.value) {
    if (!byCat.has(it.category)) byCat.set(it.category, new Map())
    const subs = byCat.get(it.category)
    const subKey = it.sub_category || '(未分類)'
    if (!subs.has(subKey)) subs.set(subKey, [])
    subs.get(subKey).push(it)
  }

  return [...byCat.entries()]
    .map(([category, subs]) => ({
      category,
      total: [...subs.values()].reduce((n, arr) => n + arr.length, 0),
      subs: [...subs.entries()]
        .map(([sub_category, list]) => ({ sub_category, list }))
        .filter((s) => s.list.length > 0)
    }))
    .filter((g) => g.total > 0)
})

const load = async () => {
  loading.value = true
  try {
    items.value = await listMistakes({
      category: filterCategory.value || undefined,
      sub_category: filterSub.value || undefined
    })
    expanded.value = grouped.value.map((g) => g.category)
  } finally {
    loading.value = false
  }
}

const remove = async (row) => {
  await ElMessageBox.confirm('削除しますか？', '確認', { type: 'warning' })
  await deleteMistake(row.id)
  ElMessage.success('削除しました')
  await load()
}

const correctText = (row) =>
  `${row.correct_option}. ${row[`option${row.correct_option}`]}`

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
            style="width: 240px"
          >
            <el-option v-for="s in subOptions" :key="s" :label="s" :value="s" />
          </el-select>
        </div>
      </div>
    </template>

    <el-empty v-if="!loading && items.length === 0" description="錯題がありません" />

    <el-collapse v-else v-model="expanded">
      <el-collapse-item
        v-for="g in grouped"
        :key="g.category"
        :name="g.category"
      >
        <template #title>
          <span class="cat-title">
            {{ g.category }}
            <el-tag size="small" type="info" round>{{ g.total }}</el-tag>
          </span>
        </template>

        <div v-for="sub in g.subs" :key="sub.sub_category" class="sub-group">
          <div class="sub-header">
            <span class="sub-name">{{ sub.sub_category }}</span>
            <el-tag size="small" type="warning" round>{{ sub.list.length }}</el-tag>
          </div>
          <el-table :data="sub.list" stripe size="small">
            <el-table-column prop="question" label="題目" show-overflow-tooltip />
            <el-table-column label="正解" width="220">
              <template #default="{ row }">{{ correctText(row) }}</template>
            </el-table-column>
            <el-table-column prop="error_count" label="間違い" width="90" sortable />
            <el-table-column label="操作" width="90">
              <template #default="{ row }">
                <el-button size="small" type="danger" @click="remove(row)">削除</el-button>
              </template>
            </el-table-column>
          </el-table>
        </div>
      </el-collapse-item>
    </el-collapse>
  </el-card>
</template>

<style scoped>
.header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.filters { display: flex; gap: 8px; }
.cat-title {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  font-size: 15px;
}
.sub-group { margin-bottom: 16px; }
.sub-group:last-child { margin-bottom: 0; }
.sub-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 8px 0;
  padding-left: 4px;
  font-size: 14px;
  color: #606266;
}
.sub-name { font-weight: 500; }
</style>
