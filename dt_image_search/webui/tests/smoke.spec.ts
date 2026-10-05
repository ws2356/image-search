import { describe, expect, it } from 'vitest'
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
})
