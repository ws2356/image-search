import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import { createPinia } from 'pinia'
import App from '../src/App.vue'

describe('App smoke', () => {
  it('renders the root container', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', component: { template: '<div class="home-stub" />' } },
        { path: '/search', component: { template: '<div />' } },
        { path: '/settings', component: { template: '<div />' } },
        { path: '/viewer/:fileId', component: { template: '<div />' } },
      ],
    })
    router.push('/')
    await router.isReady()

    const wrapper = mount(App, {
      global: { plugins: [router, createPinia()] },
    })

    expect(wrapper.find('.app-root').exists()).toBe(true)
    expect(wrapper.find('.home-stub').exists()).toBe(true)
  })

  it('renders navigation to browse, search and settings', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', component: { template: '<div />' } },
        { path: '/search', component: { template: '<div />' } },
        { path: '/settings', component: { template: '<div />' } },
        { path: '/viewer/:fileId', component: { template: '<div />' } },
      ],
    })
    router.push('/')
    await router.isReady()

    const wrapper = mount(App, { global: { plugins: [router, createPinia()] } })

    const items = wrapper.findAll('.el-menu-item')
    expect(items.map((li) => li.text())).toEqual(['浏览', '搜索', '设置'])
    await items[1].trigger('click')
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/search'))
  })
})
