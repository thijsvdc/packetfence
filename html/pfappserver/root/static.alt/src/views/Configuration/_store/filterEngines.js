/**
* "$_filter_engines" store module
*/
import Vue from 'vue'
import api from '../_api'
import store from '@/store'

const types = {
  LOADING: 'loading',
  DELETING: 'deleting',
  SUCCESS: 'success',
  ERROR: 'error'
}

// Default values
const state = {
  cache: false, // item details
  message: '',
  itemStatus: '',
  collectionsStatus: ''
}

const getters = {
  isLoadingCollections: state => state.collectionsStatus === types.LOADING,
  isLoadingCollection: state => collection => !(collection in state.cache) || !('items' in state.cache[collection]),

  isWaiting: state => [types.LOADING, types.DELETING].includes(state.itemStatus),
  isLoading: state => state.collectionsStatus === types.LOADING || state.itemStatus === types.LOADING,

  collectionToName: state => collection => {
    const { cache: { [collection]: { name } = {} } = {} } = state
    return name
  }
}

const actions = {
  getCollections: ({ state, commit }) => {
    if (state.cache) {
      return Promise.resolve(state.cache).then(collection => Object.values(collection))
    }
    commit('COLLECTIONS_REQUEST')
    return api.filterEnginesCollections().then(response => {
      commit('COLLECTIONS_REPLACED', response.items)
      return Object.values(state.cache)
    }).catch(err => {
      commit('COLLECTIONS_ERROR', err.response)
      throw err
    })
  },
  getCollection: ({ state, commit, dispatch }, collection) => {
    if (state.cache[collection] && 'items' in state.cache[collection]) {
      return Promise.resolve(state.cache[collection]).then(collection => collection)
    }
    return dispatch('getCollections').then(() => {
      commit('COLLECTION_REQUEST')
      return api.filterEnginesCollection(collection).then(response => {
        const { items } = response
        commit('COLLECTION_REPLACED', { collection, items })
        return state.cache[collection]
      }).catch(err => {
        commit('COLLECTION_ERROR', err.response)
        throw err
      })
    })
  },
  sortCollection: ({ commit, dispatch }, { collection, data }) => {
    return dispatch('getCollection', collection).then(() => {
      const params = {
        items: data,
        quiet: true
      }
      commit('COLLECTION_REQUEST', types.LOADING)
      return api.sortFilterEngines({ collection, params }).then(response => {
        commit('COLLECTION_RESORTED', { collection, params })
        return response
      }).catch(err => {
        commit('COLLECTION_ERROR', err.response)
        throw err
      })
    })
  },
  getFilterEngine: ({ state, commit, dispatch }, { collection, id }) => {
    if (state.cache[collection] && state.cache[collection].items && state.cache[collection].items.filter(item => item.id === id).length > 0) {
      return Promise.resolve(state.cache[collection].items.find(item => item.id === id)).then(filterEngine => filterEngine)
    }
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      const { [collection]: { resource } = {} } = state.cache
      return api.filterEngine({ resource, id }).then(item => {
        commit('ITEM_REPLACED', { collection, id, item })
        return state.cache[collection].items.find(item => item.id === id)
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  options: ({ commit, dispatch }, { collection, id }) => {
    if (id) {
      return dispatch('getCollection', collection).then(() => {
        commit('ITEM_REQUEST')
        const { [collection]: { resource } = {} } = state.cache
        return api.filterEngineOptions({ resource, id }).then(response => {
          commit('ITEM_SUCCESS')
          return response
        }).catch(err => {
          commit('ITEM_ERROR', err.response)
          throw err
        })
      })
    } else {
      commit('ITEM_REQUEST')
      return api.filterEnginesOptions(collection).then(response => {
        commit('ITEM_SUCCESS')
        return response
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    }
  },
  createFilterEngine: ({ commit, dispatch }, { collection, data }) => {
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      return api.createFilterEngine({ collection, data }).then(response => {
        const { id } = data
        commit('ITEM_CREATED', { collection, id, item: data })
        store.commit('config/FILTER_ENGINES_DELETED') // purge config cache
        return response
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  updateFilterEngine: ({ commit, dispatch }, { collection, id, data }) => {
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      const { [collection]: { resource } = {} } = state.cache
      return api.updateFilterEngine({ resource, id, data }).then(response => {
        commit('ITEM_REPLACED', { collection, id, item: data })
        store.commit('config/FILTER_ENGINES_DELETED') // purge config cache
        return state.cache[collection].items.find(item => item.id === id)
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  deleteFilterEngine: ({ commit, dispatch }, { collection, id }) => {
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      const { [collection]: { resource } = {} } = state.cache
      return api.deleteFilterEngine({ resource, id }).then(response => {
        commit('ITEM_DESTROYED', { collection, id })
        store.commit('config/FILTER_ENGINES_DELETED') // purge config cache
        return response
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  enableFilterEngine: ({ commit, dispatch }, { collection, id }) => {
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      const { [collection]: { resource } = {} } = state.cache
      const data = { id, status: 'enabled', quiet: true }
      return api.updateFilterEngine({ resource, id, data }).then(response => {
        commit('ITEM_ENABLED', { collection, id })
        return response
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  disableFilterEngine: ({ commit, dispatch }, { collection, id }) => {
    return dispatch('getCollection', collection).then(() => {
      commit('ITEM_REQUEST')
      const { [collection]: { resource } = {} } = state.cache
      const data = { id, status: 'disabled', quiet: true }
      return api.updateFilterEngine({ resource, id, data }).then(response => {
        commit('ITEM_DISABLED', { collection, id })
        return response
      }).catch(err => {
        commit('ITEM_ERROR', err.response)
        throw err
      })
    })
  },
  stringifyCondition: ({ commit }, json) => {
    return api.flattenCondition({ condition: json }).then(response => {
      const { item: { condition_string } = {} } = response
      return condition_string
    }).catch(err => {
      throw err
    })
  },
  parseCondition: ({ commit }, string) => {
    return api.parseCondition({ condition: string }).then(response => {
      const { item: { condition } = {} } = response
      return condition
    }).catch(err => {
      throw err
    })
  }
}

const mutations = {
  COLLECTIONS_REQUEST: (state, type) => {
    state.collectionsStatus = type || types.LOADING
    state.message = ''
  },
  COLLECTIONS_REPLACED: (state, items) => {
    state.collectionsStatus = types.SUCCESS
    Vue.set(state, 'cache', items.reduce((items, item) => {
      const { collection } = item
      items[collection] = item
      return items
    }, {}))
  },
  COLLECTIONS_ERROR: (state, response) => {
    state.collectionsStatus = types.ERROR
    if (response && response.data) {
      state.message = response.data.message
    }
  },

  COLLECTION_REQUEST: (state, type) => {
    state.itemStatus = type || types.LOADING
    state.message = ''
  },
  COLLECTION_REPLACED: (state, { collection, items }) => {
    state.itemStatus = types.SUCCESS
    if (!(collection in state.cache)) {
      Vue.set(state.cache, collection, {})
    }
    Vue.set(state.cache[collection], 'items', items)
  },
  COLLECTION_RESORTED: (state, { collection, params }) => {
    state.itemStatus = types.SUCCESS
    const { items: order } = params
    let items = Object.values(state.cache[collection].items).sort((a, b) => {
      return order.findIndex(i => i === a.id) - order.findIndex(i => i === b.id)
    })
    Vue.set(state.cache[collection], 'items', items)
  },
  COLLECTION_ERROR: (state, response) => {
    state.itemStatus = types.ERROR
    if (response && response.data) {
      state.message = response.data.message
    }
  },

  ITEM_REQUEST: (state, type) => {
    state.itemStatus = type || types.LOADING
    state.message = ''
  },
  ITEM_CREATED: (state, { collection, item }) => {
    state.itemStatus = types.SUCCESS
    if (!(collection in state.cache)) {
      Vue.set(state.cache, collection, {})
    }
    if (!('items' in state.cache[collection])) {
      Vue.set(state.cache[collection], 'items', [])
    }
    Vue.set(state.cache[collection], 'items', [
      ...state.cache[collection].items,
      {
        ...item,
        ...{ not_deletable: false, not_sortable: false }
      }
    ])
  },
  ITEM_REPLACED: (state, { collection, id, item }) => {
    state.itemStatus = types.SUCCESS
    if (!(collection in state.cache)) {
      Vue.set(state.cache, collection, {})
    }
    if (!('items' in state.cache[collection])) {
      Vue.set(state.cache[collection], 'items', [])
    }
    Vue.set(state.cache[collection], 'items', state.cache[collection].items.map(_item => {
      return (_item.id === id)
        ? item
        : _item
    }))
  },
  ITEM_DESTROYED: (state, { collection, id }) => {
    state.itemStatus = types.SUCCESS
    Vue.set(state.cache[collection], 'items', state.cache[collection].items.filter(item => {
      return (item.id !== id)
    }))
  },
  ITEM_ENABLED: (state, { collection, id }) => {
    state.itemStatus = types.SUCCESS
    Vue.set(state.cache[collection], 'items', state.cache[collection].items.map(item => {
      return (item.id === id)
        ? { ...item, ...{ status: 'enabled' } }
        : item
    }))
  },
  ITEM_DISABLED: (state, { collection, id }) => {
    state.itemStatus = types.SUCCESS
    Vue.set(state.cache[collection], 'items', state.cache[collection].items.map(item => {
      return (item.id === id)
        ? { ...item, ...{ status: 'disabled' } }
        : item
    }))
  },
  ITEM_SUCCESS: (state) => {
    state.itemStatus = types.SUCCESS
    state.message = ''
  },
  ITEM_ERROR: (state, response) => {
    state.itemStatus = types.ERROR
    if (response && response.data) {
      state.message = response.data.message
    }
  }
}

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations
}