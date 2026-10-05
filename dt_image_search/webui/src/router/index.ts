import { createRouter, createWebHistory } from 'vue-router'

// Views are placeholders in this task; Tasks 11-12 replace them with the
// real search/browse/viewer/settings implementations.
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'browse', component: () => import('@/views/BrowseView.vue') },
    { path: '/search', name: 'search', component: () => import('@/views/SearchView.vue') },
    { path: '/settings', name: 'settings', component: () => import('@/views/SettingsView.vue') },
    { path: '/viewer/:fileId', name: 'viewer', component: () => import('@/views/ViewerView.vue') },
  ],
})

export default router
