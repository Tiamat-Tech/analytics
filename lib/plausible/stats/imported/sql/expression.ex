defmodule Plausible.Stats.Imported.SQL.Expression do
  @moduledoc """
  This module is responsible for generating SQL/Ecto expressions
  for dimensions, filters and metrics used in import table queries
  """

  use Plausible.Stats.SQL.Fragments

  import Plausible.Stats.Util, only: [shortname: 2]
  import Ecto.Query

  alias Plausible.Stats.Query

  @no_ref "Direct / None"
  @not_set "(not set)"
  @none "(none)"

  def select_imported_metrics(
        %Ecto.Query{from: %Ecto.Query.FromExpr{source: {table, _}}} = q,
        query
      ) do
    select_clause =
      query.metrics
      |> Enum.map(&select_metric(&1, table, query))
      |> Enum.reduce(%{}, &Map.merge/2)

    q
    |> select_merge(q, ^select_clause)
    |> filter_pageviews(query.metrics, table)
  end

  defp filter_pageviews(q, metrics, table) do
    should_filter = :pageviews in metrics or :views_per_visit in metrics

    case {should_filter, table} do
      {_, "imported_custom_events"} -> q
      {true, _} -> q |> where([i], i.pageviews > 0)
      {false, _} -> q
    end
  end

  defp select_metric(:visitors, _table, _query) do
    wrap_alias([i], %{visitors: sum(i.visitors)})
  end

  defp select_metric(:events, "imported_custom_events", _query) do
    wrap_alias([i], %{events: sum(i.events)})
  end

  defp select_metric(:events, _table, _query) do
    wrap_alias([i], %{events: sum(i.pageviews)})
  end

  defp select_metric(:visits, "imported_exit_pages", _query) do
    wrap_alias([i], %{visits: sum(i.exits)})
  end

  defp select_metric(:visits, "imported_entry_pages", _query) do
    wrap_alias([i], %{visits: sum(i.entrances)})
  end

  defp select_metric(:visits, _table, _query) do
    wrap_alias([i], %{visits: sum(i.visits)})
  end

  defp select_metric(:pageviews, "imported_custom_events", _query) do
    wrap_alias([i], %{pageviews: 0})
  end

  defp select_metric(:pageviews, _table, _query) do
    wrap_alias([i], %{pageviews: sum(i.pageviews)})
  end

  defp select_metric(:bounce_rate, "imported_pages", _query) do
    wrap_alias([i], %{bounces: 0, __internal_visits: 0})
  end

  defp select_metric(:bounce_rate, "imported_exit_pages", _query) do
    wrap_alias([i], %{bounces: sum(i.bounces), __internal_visits: sum(i.exits)})
  end

  defp select_metric(:bounce_rate, "imported_entry_pages", _query) do
    wrap_alias([i], %{bounces: sum(i.bounces), __internal_visits: sum(i.entrances)})
  end

  defp select_metric(:bounce_rate, _table, _query) do
    wrap_alias([i], %{bounces: sum(i.bounces), __internal_visits: sum(i.visits)})
  end

  defp select_metric(:exit_rate, "imported_exit_pages", _query) do
    wrap_alias([i], %{__internal_visits: sum(i.exits)})
  end

  defp select_metric(:visit_duration, "imported_pages", _query) do
    wrap_alias([i], %{visit_duration: 0})
  end

  defp select_metric(:visit_duration, "imported_exit_pages", _query) do
    wrap_alias([i], %{visit_duration: sum(i.visit_duration), __internal_visits: sum(i.exits)})
  end

  defp select_metric(:visit_duration, "imported_entry_pages", _query) do
    wrap_alias([i], %{visit_duration: sum(i.visit_duration), __internal_visits: sum(i.entrances)})
  end

  defp select_metric(:visit_duration, _table, _query) do
    wrap_alias([i], %{visit_duration: sum(i.visit_duration), __internal_visits: sum(i.visits)})
  end

  defp select_metric(:views_per_visit, "imported_exit_pages", _query) do
    wrap_alias([i], %{pageviews: sum(i.pageviews), __internal_visits: sum(i.exits)})
  end

  defp select_metric(:views_per_visit, "imported_entry_pages", _query) do
    wrap_alias([i], %{pageviews: sum(i.pageviews), __internal_visits: sum(i.entrances)})
  end

  defp select_metric(:views_per_visit, _table, _query) do
    wrap_alias([i], %{pageviews: sum(i.pageviews), __internal_visits: sum(i.visits)})
  end

  defp select_metric(:scroll_depth, "imported_pages", _query) do
    wrap_alias([i], %{
      total_scroll_depth: sum(i.total_scroll_depth),
      total_scroll_depth_visits: sum(i.total_scroll_depth_visits)
    })
  end

  defp select_metric(:time_on_page, "imported_pages", query) do
    case query.time_on_page_data do
      %{include_new_metric: false} ->
        wrap_alias([i], %{
          total_time_on_page: 0,
          total_time_on_page_visits: 0
        })

      %{include_new_metric: true, cutoff: nil} ->
        wrap_alias([i], %{
          total_time_on_page: sum(i.total_time_on_page),
          total_time_on_page_visits: sum(i.total_time_on_page_visits)
        })

      %{include_new_metric: true, cutoff: cutoff} ->
        cutoff_date = cutoff |> DateTime.shift_zone!(query.timezone) |> DateTime.to_date()

        wrap_alias([i], %{
          total_time_on_page:
            fragment("sumIf(?, ? >= ?)", i.total_time_on_page, i.date, ^cutoff_date),
          total_time_on_page_visits:
            fragment("sumIf(?, ? >= ?)", i.total_time_on_page_visits, i.date, ^cutoff_date)
        })
    end
  end

  defp select_metric(_metric, _table, _query), do: %{}

  def group_imported_by(q, query) do
    Enum.reduce(query.dimensions, q, fn dimension, q ->
      q
      |> select_group_fields(dimension, shortname(query, dimension), query)
      |> filter_group_values(dimension)
      |> group_by([], selected_as(^shortname(query, dimension)))
    end)
  end

  defp select_group_fields(q, dimension, key, _query)
       when dimension in ["visit:source", "visit:referrer"] do
    select_merge_as(q, [i], %{
      key =>
        fragment(
          "if(empty(?), ?, ?)",
          field(i, ^dim(dimension)),
          @no_ref,
          field(i, ^dim(dimension))
        )
    })
  end

  defp select_group_fields(q, "event:page", key, _query) do
    select_merge_as(q, [i], %{key => i.page})
  end

  defp select_group_fields(q, dimension, key, _query)
       when dimension in ["visit:device", "visit:browser", "visit:channel"] do
    select_merge_as(q, [i], %{
      key =>
        fragment(
          "if(empty(?), ?, ?)",
          field(i, ^dim(dimension)),
          @not_set,
          field(i, ^dim(dimension))
        )
    })
  end

  defp select_group_fields(q, "visit:browser_version", key, _query) do
    select_merge_as(q, [i], %{
      key => fragment("if(empty(?), ?, ?)", i.browser_version, @not_set, i.browser_version)
    })
  end

  defp select_group_fields(q, "visit:os", key, _query) do
    select_merge_as(q, [i], %{
      key => fragment("if(empty(?), ?, ?)", i.operating_system, @not_set, i.operating_system)
    })
  end

  defp select_group_fields(q, "visit:os_version", key, _query) do
    select_merge_as(q, [i], %{
      key =>
        fragment(
          "if(empty(?), ?, ?)",
          i.operating_system_version,
          @not_set,
          i.operating_system_version
        )
    })
  end

  defp select_group_fields(q, "event:props:url", key, _query) do
    select_merge_as(q, [i], %{
      key => fragment("if(not empty(?), ?, ?)", i.link_url, i.link_url, @none)
    })
  end

  defp select_group_fields(q, "event:props:path", key, _query) do
    select_merge_as(q, [i], %{
      key => fragment("if(not empty(?), ?, ?)", i.path, i.path, @none)
    })
  end

  defp select_group_fields(q, "time:month", key, _query) do
    select_merge_as(q, [i], %{key => fragment("toStartOfMonth(?)", i.date)})
  end

  defp select_group_fields(q, dimension, key, _query)
       when dimension in ["time:hour", "time:day"] do
    select_merge_as(q, [i], %{key => i.date})
  end

  defp select_group_fields(q, "time:week", key, query) do
    date_range = Query.date_range(query)

    select_merge_as(q, [i], %{
      key => weekstart_not_before(i.date, ^date_range.first)
    })
  end

  defp select_group_fields(q, dimension, key, _query) do
    select_merge_as(q, [i], %{key => field(i, ^dim(dimension))})
  end

  @utm_dimensions [
    "visit:utm_source",
    "visit:utm_medium",
    "visit:utm_campaign",
    "visit:utm_term",
    "visit:utm_content"
  ]
  defp filter_group_values(q, dimension) when dimension in @utm_dimensions do
    dim = Plausible.Stats.Filters.without_prefix(dimension)

    where(q, [i], fragment("not empty(?)", field(i, ^dim)))
  end

  defp filter_group_values(q, "visit:country"), do: where(q, [i], i.country != "ZZ")
  defp filter_group_values(q, "visit:region"), do: where(q, [i], i.region != "")
  defp filter_group_values(q, "visit:city"), do: where(q, [i], i.city != 0 and not is_nil(i.city))

  defp filter_group_values(q, "visit:country_name"), do: where(q, [i], i.country_name != "ZZ")
  defp filter_group_values(q, "visit:region_name"), do: where(q, [i], i.region_name != "")
  defp filter_group_values(q, "visit:city_name"), do: where(q, [i], i.city_name != "")

  defp filter_group_values(q, _dimension), do: q

  def select_joined_dimensions(q, query) do
    Enum.reduce(query.dimensions, q, fn dimension, q ->
      select_joined_dimension(q, dimension, shortname(query, dimension))
    end)
  end

  defp select_joined_dimension(q, "visit:city", key) do
    select_merge_as(q, [s, i], %{
      key => fragment("greatest(?,?)", field(i, ^key), field(s, ^key))
    })
  end

  defp select_joined_dimension(q, "time:" <> _, key) do
    select_merge_as(q, [s, i], %{
      key => fragment("greatest(?, ?)", field(i, ^key), field(s, ^key))
    })
  end

  defp select_joined_dimension(q, _dimension, key) do
    select_merge_as(q, [s, i], %{
      key => fragment("if(empty(?), ?, ?)", field(s, ^key), field(i, ^key), field(s, ^key))
    })
  end

  def select_joined_metrics(q, query) do
    select_metrics =
      query.metrics
      |> Enum.map(&joined_metric(&1, query))
      |> Enum.reduce(%{}, &Map.merge/2)

    select_merge(q, ^select_metrics)
  end

  # NOTE: Reverse-engineering the native data bounces and total visit
  # durations to combine with imported data is inefficient. Instead both
  # queries should fetch bounces/total_visit_duration and visits and be
  # used as subqueries to a main query that then find the bounce rate/avg
  # visit_duration.

  defp joined_metric(:visits, _query) do
    wrap_alias([s, i], %{visits: s.visits + i.visits})
  end

  defp joined_metric(:visitors, _query) do
    wrap_alias([s, i], %{visitors: s.visitors + i.visitors})
  end

  defp joined_metric(:events, _query) do
    wrap_alias([s, i], %{events: s.events + i.events})
  end

  defp joined_metric(:pageviews, _query) do
    wrap_alias([s, i], %{pageviews: s.pageviews + i.pageviews})
  end

  defp joined_metric(:views_per_visit, _query) do
    wrap_alias([s, i], %{
      views_per_visit:
        fragment(
          "if(? + ? > 0, round((? + ? * ?) / (? + ?), 2), 0)",
          s.__internal_visits,
          i.__internal_visits,
          i.pageviews,
          s.views_per_visit,
          s.__internal_visits,
          i.__internal_visits,
          s.__internal_visits
        )
    })
  end

  defp joined_metric(:bounce_rate, _query) do
    wrap_alias([s, i], %{
      bounce_rate:
        fragment(
          "if(? + ? > 0, round(100 * (? + (? * ? / 100)) / (? + ?)), 0)",
          s.__internal_visits,
          i.__internal_visits,
          i.bounces,
          s.bounce_rate,
          s.__internal_visits,
          i.__internal_visits,
          s.__internal_visits
        )
    })
  end

  defp joined_metric(:visit_duration, _query) do
    wrap_alias([s, i], %{
      visit_duration:
        fragment(
          """
          if(
            ? + ? > 0,
            round((? + ? * ?) / (? + ?), 0),
            0
          )
          """,
          s.__internal_visits,
          i.__internal_visits,
          i.visit_duration,
          s.visit_duration,
          s.__internal_visits,
          s.__internal_visits,
          i.__internal_visits
        )
    })
  end

  # The final `scroll_depth` gets selected at a later querybuilding step
  # (in `Plausible.Stats.SQL.SpecialMetrics.add/3`). But in order to avoid
  # having to join with imported data there again, we select the required
  # information from imported data here already.
  defp joined_metric(:scroll_depth, _query) do
    wrap_alias([s, i], %{
      __imported_total_scroll_depth: i.total_scroll_depth,
      __imported_total_scroll_depth_visits: i.total_scroll_depth_visits
    })
  end

  defp joined_metric(:time_on_page, query) do
    wrap_alias([s, i], %{
      __internal_total_time_on_page: s.__internal_total_time_on_page + i.total_time_on_page,
      __internal_total_time_on_page_visits:
        s.__internal_total_time_on_page_visits + i.total_time_on_page_visits
    })
    |> Map.merge(time_on_page_metric(query))
  end

  defp joined_metric(:exit_rate, _query) do
    wrap_alias([s, i], %{
      __internal_visits: s.__internal_visits + i.__internal_visits
    })
  end

  # Ignored as it's calculated separately
  defp joined_metric(metric, _query)
       when metric in [:conversion_rate, :group_conversion_rate, :percentage] do
    %{}
  end

  defp joined_metric(metric, _query) do
    wrap_alias([s, i], %{metric => field(s, ^metric)})
  end

  defp dim(dimension), do: Plausible.Stats.Filters.without_prefix(dimension)

  defp time_on_page_metric(query) do
    if query.time_on_page_data.include_legacy_metric do
      %{}
    else
      wrap_alias([], %{
        time_on_page:
          time_on_page(
            selected_as(:__internal_total_time_on_page),
            selected_as(:__internal_total_time_on_page_visits)
          )
      })
    end
  end
end
