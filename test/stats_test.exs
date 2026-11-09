defmodule PrologEx.StatsTest do
  # library(stats): beschreibende Statistik, exakt ohne Floats
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @s "[2,4,4,4,5,5,7,9]"

  @rows [
    # Lage
    {"mean([1,2,2], M)", ["M = 5r3"]},
    {"mean([1,2.0], M)", ["M = 1.5"]},
    {"mean([1r2, 1r3], M)", ["M = 5r12"]},
    {"mean([0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1], M)", ["M = 0.1"]},
    {"median([3,1,4,1,5,9], M), median([3,1,4], M2)", ["M = 7r2, M2 = 3"]},
    {"modes([1,2,2,3,3,1r2], M)", ["M = [2,3]"]},
    {"harmonic_mean([1,2,4], H), geometric_mean([1,2,4], G)", ["G = 2.0, H = 12r7"]},
    {"weighted_mean([1,2,3], [10,20,30], M)", ["M = 70r3"]},
    {"trimmed_mean([1,2,3,4,100], 1r5, M), trimmed_mean([1,2,3,4,100], 0, M0)",
     ["M = 3, M0 = 22"]},
    # Quantile
    {"quartiles([1,2,3,4,5,6,7,8], Q1, Q2, Q3), interquartile_range([1,2,3,4,5,6,7,8], R)",
     ["Q1 = 11r4, Q2 = 9r2, Q3 = 25r4, R = 7r2"]},
    {"percentile(90, [10,20,30,40], P), percentile(0, [10,20,30,40], P0), " <>
       "percentile(100, [10,20,30,40], P1)", ["P = 37, P0 = 10, P1 = 40"]},
    {"fractile(1r2, [10,20,30,40], F), fractile(1, [10,20,30,40], F1), " <>
       "fractile(0.01, [10,20,30,40], F0)", ["F = 20, F0 = 10, F1 = 40"]},
    {"fractile(0, [1], F)", {:error, "domain_error(fractile,0)"}},
    {"percentile(101, [1], F)", {:error, "domain_error(percentile,101)"}},
    # Streuung
    {"min_max([3,1r2,2.5], A, B), range([3,1r2,2.5], R), min([4,2], Mi), max([4,2], Ma)",
     ["A = 1r2, B = 3, Ma = 4, Mi = 2, R = 5r2"]},
    {"sample_variance(#{@s}, V), population_variance(#{@s}, P)", ["P = 4, V = 32r7"]},
    {"population_standard_deviation(#{@s}, SD)", ["SD = 2.0"]},
    {"sample_standard_deviation(#{@s}, SD)", ["SD = 2.138089935299395"]},
    {"standard_error(#{@s}, SE), coefficient_of_variation(#{@s}, CV)",
     ["CV = 0.427617987059879, SE = 0.7559289460184544"]},
    {"weighted_variance([1,1], [1,3], V), weighted_variance([3,1], [1,3], V2)",
     ["V = 1, V2 = 3r4"]},
    {"mean_deviation([1,2,3,10], D), median_deviation([1,2,3,10], M)", ["D = 3, M = 1"]},
    # stabil auch bei großem Mittelwert (nicht E[x²] - E[x]²)
    {"sample_variance([1000000000.0, 1000000001.0, 1000000002.0], V)", ["V = 1.0"]},
    {"sample_variance([100000000000000000000, 100000000000000000001], V)", ["V = 1r2"]},
    # Form
    {"central_moment(3, [1,2,3,10], C), skewness([1,2,3,10], S), kurtosis([1,2,3,10], K)",
     ["C = 45, K = -481r625, S = 1.0182337649086284"]},
    {"central_moment(0, [1], C)", {:error, "domain_error(not_less_than_one,0)"}},
    # Zusammenhang
    {"sample_covariance([1,2,3], [2,4,7], C), population_covariance([1,2,3], [2,4,7], P)",
     ["C = 5r2, P = 5r3"]},
    {"correlation([1,2,3], [2,4,6], R), correlation([1,2,3], [3,2,1], R2)",
     ["R = 1.0, R2 = -1.0"]},
    {"rank_correlation([1,2,3,4], [10,20,20,40], R)", ["R = 0.9486832980505138"]},
    {"rank_correlation([1,2,3], [1,4,9], R)", ["R = 1.0"]},
    # Sonst
    {"z_normalization([1,2,3], Z)", ["Z = [-1.224744871391589,0.0,1.224744871391589]"]},
    {"min_max_normalization([1,2,5], N)", ["N = [0,1r4,1]"]},
    {"frequency_distribution([3,1,1,2], F)", ["F = [1-2,2-1,3-1]"]},
    # undefiniert und Fehler
    {"mean([], M)", {:error, "evaluation_error(undefined)"}},
    {"sample_variance([1], V)", {:error, "evaluation_error(undefined)"}},
    {"skewness([2,2,2], S)", {:error, "evaluation_error(undefined)"}},
    {"correlation([1,1,1], [1,2,3], R)", {:error, "evaluation_error(undefined)"}},
    {"geometric_mean([1,0], G)", {:error, "evaluation_error(undefined)"}},
    {"harmonic_mean([1,0], G)", {:error, "evaluation_error(undefined)"}},
    {"mean([1,a], M)", {:error, "type_error(number,a)"}},
    {"mean(_, M)", {:error, "instantiation_error"}},
    {"mean([1|_], M)", {:error, "instantiation_error"}},
    {"mean([1,_], M)", {:error, "instantiation_error"}},
    {"mean(foo, M)", {:error, "type_error(list,foo)"}},
    {"correlation([1,2], [1,2,3], R)", {:error, "domain_error(same_length,"}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists stats))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
