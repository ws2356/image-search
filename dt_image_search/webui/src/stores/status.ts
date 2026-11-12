// Shared server snapshot for search readiness, folder badges and settings.
// Author: Codex
// Created: 2026-11-13
import { computed, onScopeDispose, ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '../api/client'
import type { StatusResponse } from '../api/types'
import { useFoldersStore } from './folders'

export const useStatusStore = defineStore('status', () => {
  const folders = useFoldersStore()
  const modelState = ref<string | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)
  let revision = 0

  const snapshot = computed<StatusResponse | null>(() => modelState.value === null ? null : {
    model_state: modelState.value,
    folders: folders.folders,
  })

  async function refresh(): Promise<boolean> {
    const requestRevision = ++revision
    loading.value = true
    error.value = null
    try {
      const response = await api.getStatus()
      if (requestRevision !== revision) return false
      modelState.value = response.model_state
      folders.folders = response.folders
      return true
    } catch {
      if (requestRevision === revision) error.value = '加载状态失败，请稍后重试'
      return false
    } finally {
      if (requestRevision === revision) loading.value = false
    }
  }

  function cancelRefresh() {
    revision += 1
    loading.value = false
  }

  onScopeDispose(cancelRefresh)

  return { modelState, snapshot, loading, error, refresh, cancelRefresh }
})
