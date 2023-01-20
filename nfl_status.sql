-- https://docs.google.com/spreadsheets/d/1KT21vWd4EiOaNOEAnl4erA8sC-83NxB-N2ftiTL8bEU/edit?usp=sharing

with constants as (
    select
        0 as home_constant,
        0 as away_constant
),
avg_scores as (
    select week, team, opponent, home_away, vegas_spread, vegas_ou, team_score, opponent_score,
        avg(team_score) over (
            partition by team
            order by week
            rows unbounded preceding exclude current row
        ) avg_points_scored,
        avg(opponent_score) over (
            partition by team
            order by week
            rows unbounded preceding exclude current row
        ) avg_points_allowed
    from nfl_analytics.nfl_stats
),
nfl_stats_stg as (
    select week, team, opponent, home_away, team_score, opponent_score,
        predicted_team_score, predicted_opponent_score, vegas_spread, actual_spread,
        (predicted_team_score - predicted_opponent_score) as predicted_spread,
        vegas_ou, final_sum, (predicted_team_score + predicted_opponent_score) predicted_sum
    from (
        select a1.week, a1.team, a1.opponent, a1.home_away, a1.team_score, a1.opponent_score,
            ((a1.avg_points_scored + a2.avg_points_allowed) / 2) + (
                case when a1.home_away='home'
                    then (select home_constant from constants)
                    else (select away_constant from constants)
                end
            ) as predicted_team_score,
            ((a2.avg_points_scored + a1.avg_points_allowed) / 2)  + (
                case when a1.home_away='away'
                    then (select away_constant from constants)
                    else (select home_constant from constants)
                end
            ) as predicted_opponent_score,
            a1.vegas_spread,
            (a1.team_score - a1.opponent_score) as actual_spread,
            a1.vegas_ou,
            (a1.team_score + a1.opponent_score) final_sum
        from avg_scores a1
        left join avg_scores a2 on
            a1.week = a2.week
            and a1.opponent = a2.team
    ) r1
),
nfl_stats as (
    select
        week,
        team,
        opponent,
        home_away,
        team_score,
        opponent_score,
        predicted_team_score,
        predicted_opponent_score,
        vegas_spread,
        actual_spread,
        predicted_spread,
        vegas_ou,
        final_sum,
        predicted_sum,
        case
            when team_score is null or opponent_score is null
            then null
            when (team_score + vegas_spread) > opponent_score
            then 'win'
            else 'lose'
        end spread_bet_result,
        case
            when predicted_team_score is null or predicted_opponent_score is null
            then null
            when (predicted_team_score + vegas_spread) > predicted_opponent_score
            then 'win'
            else 'lose'
        end spread_bet_prediction,
        case
            when team_score is null or opponent_score is null
            then null
            when final_sum > vegas_ou
            then 'over'
            when final_sum < vegas_ou
            then 'under'
            else 'equal'
        end ou_bet_result,
        case
            when predicted_team_score is null or predicted_opponent_score is null
            then null
            when predicted_sum > vegas_ou
            then 'over'
            when predicted_sum < vegas_ou
            then 'under'
            else 'equal'
        end ou_bet_prediction
    from nfl_stats_stg
),
final_raw_data as (
    select week,
        team,
        opponent,
        home_away,
        team_score,
        opponent_score,
        predicted_team_score,
        predicted_opponent_score,
        vegas_spread,
        actual_spread,
        predicted_spread,
        vegas_ou,
        final_sum,
        predicted_sum,
        spread_bet_result,
        spread_bet_prediction,
        case when spread_bet_result is null or spread_bet_prediction is null
            then null
            when spread_bet_result = 'win' and spread_bet_prediction = 'win'
            then 'win'
            else 'lose'
        end prediction_spread_result,
        ou_bet_result,
        ou_bet_prediction,
        case when ou_bet_result is null or ou_bet_prediction is null
            then null
            when ou_bet_result = ou_bet_prediction and ou_bet_result <> ' equal'
            then 'win'
            else 'lose'
        end prediction_ou_result,
        (predicted_spread - vegas_spread) spread_diff,
        (final_sum -  vegas_ou) as ou_diff,
        (predicted_sum -  vegas_ou) as ou_predicted_diff
    from nfl_stats
)
select *
from final_raw_data
order by 1, 2

-- begin constants
/*
series as (
    select generate_series as x
    from generate_series(0.01, 1.99, 0.01)
),
constants as (
    select a.x team_alpha, b.x opponent_alpha
    from series a
    cross join series b
    order by 1, 2
),
prediction_alpha as (
    select a.week, a.vegas_spread, a.spread_bet_result, b.team_alpha, b.opponent_alpha,
        a.predicted_team_score * b.team_alpha as predicted_team_score_alpha,
        a.predicted_opponent_score * b.opponent_alpha as predicted_opponents_score_alpha
    from final_raw_data a
    cross join constants b
),
prediction_result_alpha as (
    select *,
        case
            when predicted_team_score_alpha is null or predicted_opponents_score_alpha is null
            then null
            when (predicted_team_score_alpha + vegas_spread) > predicted_opponents_score_alpha
            then 'win'
            else 'lose'
        end spread_bet_prediction_alpha
    from prediction_alpha
),
prediction_comparison_alpha as (
    select *,
        case when spread_bet_result is null or spread_bet_prediction_alpha is null
            then null
            when spread_bet_result = 'win' and spread_bet_prediction_alpha = 'win'
            then 'win'
            else 'lose'
        end prediction_spread_result_alpha
    from prediction_result_alpha
),
final_constants_by_week as (
    select week, prediction_spread_result_alpha,
        percentile_cont(0.5) within group (order by team_alpha) team_alpha_avg,
        percentile_cont(0.5) within group (order by opponent_alpha) opponent_alpha_avg
    from (
        select week, prediction_spread_result_alpha, team_alpha, opponent_alpha -- , count(1) cnt
            --median(team_alpha), median(opponent_alpha),
            --percentile_cont(0.5) within group (order by team_alpha),
            --percentile_cont(0.5) within group (order by opponent_alpha)
        from prediction_comparison_alpha
        where prediction_spread_result_alpha = 'win'
        group by 1, 2, 3, 4
        having count(1) = 16
    ) r
    group by 1, 2
),
final_constants_avg as (
    select avg(team_alpha_avg) as team_alpha_avg,
        avg(opponent_alpha_avg) as opponent_alpha_avg
    from final_constants_by_week
)
-- end constants

select a.*,
    case
        when a.predicted_team_score is null or a.predicted_opponent_score is null
        then null
        when ((a.predicted_team_score *  b.team_alpha_avg) + vegas_spread) > (a.predicted_opponent_score * b.opponent_alpha_avg)
        then 'win'
        else 'lose'
    end spread_bet_prediction_alpha,
    b.team_alpha_avg,
    b.opponent_alpha_avg,
    (a.predicted_team_score *  b.team_alpha_avg) team_prediction_alpha,
    (a.predicted_opponent_score * b.opponent_alpha_avg) opponent_prediction_alpha
from final_raw_data a
cross join final_constants_avg b
order by week, team
 */
-- end series

