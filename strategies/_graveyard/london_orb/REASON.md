# Why london_orb was retired

Range-breakout-continuation on the pre-London (06:00–08:00 server time)
range, EURUSD.r, M15, in-sample 2018–2022. Three structurally different
entry filters (tick-touch, bar-close + minimum range size, + higher-
timeframe trend alignment) all converged on ~32-33% win rate and ~0.78-0.81
profit factor — evidence the "breakout predicts continuation" thesis has
no real edge here, not that the filter needed more tuning. See v1/v2/v3
review.md for full detail. All three versions lost money specifically by
trading *with* the breakout direction, which is why the next strategy
tests fading it instead.
