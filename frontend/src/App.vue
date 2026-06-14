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
* { box-sizing: border-box; }
.app { height: 100%; }
.header {
  display: flex;
  align-items: center;
  gap: 24px;
  border-bottom: 1px solid #e4e7ed;
  background: #fff;
}
.brand { font-weight: 600; font-size: 18px; white-space: nowrap; }
.el-main { max-width: 960px; margin: 0 auto; width: 100%; }

/* ===== モバイル対応（iPhone など狭い画面）===== */
@media (max-width: 600px) {
  /* ヘッダー：縦積み + メニューを均等割付（横溢れを解消） */
  .header {
    height: auto !important;
    flex-direction: column;
    align-items: stretch;
    gap: 0;
    padding: 6px 8px;
  }
  .brand {
    font-size: 16px;
    text-align: center;
    padding: 6px 0;
    white-space: normal;
  }
  .header .el-menu.el-menu--horizontal {
    width: 100%;
    display: flex;
    border-bottom: none;
  }
  .header .el-menu--horizontal > .el-menu-item {
    flex: 1;
    padding: 0 6px;
    font-size: 14px;
    justify-content: center;
    height: 48px;
    line-height: 48px;
  }
  /* メイン領域・カードの余白を圧縮 */
  .el-main { padding: 10px !important; }
  .el-card__body { padding: 12px !important; }
  .el-card__header { padding: 12px !important; }
  /* 固定幅セレクト・インラインフォームを全幅に */
  .el-select { width: 100% !important; }
  .el-form--inline .el-form-item {
    display: block;
    margin-right: 0;
    width: 100%;
  }
  .el-form--inline .el-form-item__content { display: block; }
  /* iOS Safari: フォーカス時の自動ズーム(font-size<16px が原因)を防ぐ */
  .el-select__wrapper,
  .el-select__input,
  .el-input__inner,
  .el-textarea__inner {
    font-size: 16px !important;
  }
}
</style>
