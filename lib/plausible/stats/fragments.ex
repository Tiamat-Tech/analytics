defmodule Plausible.Stats.Fragments do
  defmacro uniq(user_id) do
    quote do
      fragment("round(uniq(?) * any(_sample_factor))", unquote(user_id))
    end
  end

  defmacro total() do
    quote do
      fragment("round(count(*) * any(_sample_factor))")
    end
  end

  defmacro bounce_rate() do
    quote do
      fragment("round(sum(is_bounce * sign) / sum(sign) * 100)")
    end
  end

  defmacro visit_duration() do
    quote do
      fragment("round(avg(duration * sign))")
    end
  end
end
