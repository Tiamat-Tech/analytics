/* eslint-disable react-hooks/exhaustive-deps */
import React, { useState, useEffect, useRef, useCallback } from 'react'
import * as api from '../../api'
import * as storage from '../../util/storage'
import TopStats from './top-stats'
import { IntervalPicker, getCurrentInterval } from './interval-picker'
import StatsExport from './stats-export'
import WithImportedSwitch from './with-imported-switch'
import { getSamplingNotice, NoticesIcon } from './notices'
import FadeIn from '../../fade-in'
import * as url from '../../util/url'
import { isComparisonEnabled } from '../../query-time-periods'
import LineGraphWithRouter from './line-graph'
import { useQueryContext } from '../../query-context'
import { useSiteContext } from '../../site-context'

function fetchTopStats(site, query) {
  const q = { ...query }

  if (!isComparisonEnabled(q.comparison) && query.period !== 'realtime') {
    q.comparison = 'previous_period'
  }

  return api.get(url.apiPath(site, '/top-stats'), q)
}

function fetchMainGraph(site, query, metric, interval) {
  const params = { metric, interval }
  return api.get(url.apiPath(site, '/main-graph'), query, params)
}

export default function VisitorGraph({ updateImportedDataInView }) {
  const { query } = useQueryContext()
  const site = useSiteContext()

  const isRealtime = query.period === 'realtime'
  const isDarkTheme =
    document.querySelector('html').classList.contains('dark') || false

  const topStatsBoundary = useRef(null)

  const [topStatData, setTopStatData] = useState(null)
  const [topStatsLoading, setTopStatsLoading] = useState(true)
  const [graphData, setGraphData] = useState(null)
  const [graphLoading, setGraphLoading] = useState(true)

  // This state is explicitly meant for the situation where either graph interval
  // or graph metric is changed. That results in behaviour where Top Stats stay
  // intact, but the graph container alone will display a loading spinner for as
  // long as new graph data is fetched.
  const [graphRefreshing, setGraphRefreshing] = useState(false)

  const onIntervalUpdate = useCallback(
    (newInterval) => {
      setGraphData(null)
      setGraphRefreshing(true)
      fetchGraphData(getStoredMetric(), newInterval)
    },
    [query]
  )

  const onMetricUpdate = useCallback(
    (newMetric) => {
      setGraphData(null)
      setGraphRefreshing(true)
      fetchGraphData(newMetric, getCurrentInterval(site, query))
    },
    [query]
  )

  useEffect(() => {
    setTopStatData(null)
    setTopStatsLoading(true)
    setGraphData(null)
    setGraphLoading(true)
    fetchTopStatsAndGraphData()

    if (isRealtime) {
      document.addEventListener('tick', fetchTopStatsAndGraphData)
    }

    return () => {
      document.removeEventListener('tick', fetchTopStatsAndGraphData)
    }
  }, [query])

  useEffect(() => {
    if (topStatData) {
      storeTopStatsContainerHeight()
    }
  }, [topStatData])

  async function fetchTopStatsAndGraphData() {
    const response = await fetchTopStats(site, query)

    let metric = getStoredMetric()
    const availableMetrics = response.graphable_metrics

    if (!availableMetrics.includes(metric)) {
      metric = availableMetrics[0]
      storage.setItem(`metric__${site.domain}`, metric)
    }

    const interval = getCurrentInterval(site, query)

    if (response.updateImportedDataInView) {
      updateImportedDataInView(response.includes_imported)
    }

    setTopStatData(response)
    setTopStatsLoading(false)

    fetchGraphData(metric, interval)
  }

  function fetchGraphData(metric, interval) {
    fetchMainGraph(site, query, metric, interval).then((res) => {
      setGraphData(res)
      setGraphLoading(false)
      setGraphRefreshing(false)
    })
  }

  function getStoredMetric() {
    return storage.getItem(`metric__${site.domain}`)
  }

  function storeTopStatsContainerHeight() {
    storage.setItem(
      `topStatsHeight__${site.domain}`,
      document.getElementById('top-stats-container').clientHeight
    )
  }

  // This function is used for maintaining the main-graph/top-stats container height in the
  // loading process. The container height depends on how many top stat metrics are returned
  // from the API, but in the loading state, we don't know that yet. We can use localStorage
  // to keep track of the Top Stats container height.
  function getTopStatsHeight() {
    if (topStatData) {
      return 'auto'
    } else {
      return `${storage.getItem(`topStatsHeight__${site.domain}`) || 89}px`
    }
  }

  function importedSwitchVisible() {
    return (
      !!topStatData?.with_imported_switch &&
      topStatData?.with_imported_switch.visible
    )
  }

  function getImportedIntervalUnsupportedNotice() {
    const unsupportedInterval = ['hour', 'minute'].includes(
      getCurrentInterval(site, query)
    )
    const showingImported =
      importedSwitchVisible() && query.with_imported === true

    if (showingImported && unsupportedInterval) {
      return 'Interval is too short to graph imported data'
    }

    return null
  }

  return (
    <div
      className={
        'relative w-full mt-2 bg-white rounded shadow-xl dark:bg-gray-825'
      }
    >
      {(topStatsLoading || graphLoading) && renderLoader()}
      <FadeIn show={!(topStatsLoading || graphLoading)}>
        <div
          id="top-stats-container"
          className="flex flex-wrap"
          ref={topStatsBoundary}
          style={{ height: getTopStatsHeight() }}
        >
          <TopStats
            graphableMetrics={topStatData?.graphable_metrics || []}
            data={topStatData}
            onMetricUpdate={onMetricUpdate}
            tooltipBoundary={topStatsBoundary.current}
          />
        </div>
        <div className="relative px-2">
          {graphRefreshing && renderLoader()}
          <div className="absolute right-4 -top-8 py-1 flex items-center gap-x-4">
            <NoticesIcon
              notices={[
                getImportedIntervalUnsupportedNotice(),
                getSamplingNotice(topStatData)
              ].filter((n) => !!n)}
            />
            {!isRealtime && <StatsExport />}
            {importedSwitchVisible() && (
              <WithImportedSwitch
                tooltipMessage={topStatData.with_imported_switch.tooltip_msg}
                disabled={!topStatData.with_imported_switch.togglable}
              />
            )}
            <IntervalPicker onIntervalUpdate={onIntervalUpdate} />
          </div>
          <LineGraphWithRouter
            graphData={{
              ...graphData,
              interval: getCurrentInterval(site, query)
            }}
            darkTheme={isDarkTheme}
          />
        </div>
      </FadeIn>
    </div>
  )
}

function renderLoader() {
  return (
    <div className="absolute h-full w-full flex items-center justify-center">
      <div className="loading">
        <div></div>
      </div>
    </div>
  )
}
