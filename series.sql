with series as (
    select generate_series as x
    from generate_series(0.01, 1.99, 0.01)
),
constants as (
    select a.x team_alpha, b.x opponent_alpha
    from series a
    cross join series b
    order by 1, 2
)
select *
from constants;

/*
create schema nfl_analytics;

truncate table nfl_analytics.nfl_stats;


create table nfl_analytics.nfl_stats (
season varchar(10),
week int,
team varchar(3),
opponent varchar(3),
vegas_spread numeric,
vegas_ou numeric,
home_away varchar(4),
team_score int,
opponent_score int
);
 */