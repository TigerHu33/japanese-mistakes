<template>
  <el-container class="app">
    <el-header class="header">
      <div class="brand">N1 錯題記録</div>
      <el-menu
        mode="horizontal"
        :default-active="$route.name"
        @select="(name) => $router.push({ name })"
        :ellipsis="false"
      >
        <el-menu-item index="list">錯題一覧</el-menu-item>
        <el-menu-item index="add">錯題録入</el-menu-item>
        <el-menu-item index="practice">練習モード</el-menu-item>
      </el-menu>
    </el-header>
    <el-main>
      <router-view />
    </el-main>
  </el-container>
</template>

<style>
html, body, #app { height: 100%; margin: 0; }
.app { height: 100%; }
.header {
  display: flex;
  align-items: center;
  gap: 24px;
  border-bottom: 1px solid #e4e7ed;
  background: #fff;
}
.brand { font-weight: 600; font-size: 18px; }
.el-main { max-width: 960px; margin: 0 auto; width: 100%; }
</style>
