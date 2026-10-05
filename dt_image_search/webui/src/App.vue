<script setup lang="ts">
// App shell: header + routed view. Element Plus components are auto-imported.
</script>

<template>
  <div class="app-root">
    <el-container class="app-container">
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </div>
</template>

<style scoped>
.app-container {
  min-height: 100vh;
}
</style>
