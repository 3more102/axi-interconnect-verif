from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from coverage_guide import SCENARIOS,choose_next,default_state,observe

def test_initial_exploration_order():
    s=default_state(); assert choose_next(s)==SCENARIOS[0]; observe(s,SCENARIOS[0],{"a"}); assert choose_next(s)==SCENARIOS[1]

def test_reward_counts_only_new_bins():
    s=default_state(); assert observe(s,"mixed",{"a","b"})==2; assert observe(s,"mixed",{"b","c"})==1; assert set(s["global_bins"])=={"a","b","c"}

def test_policy_returns_known_scenario():
    s=default_state()
    for name in SCENARIOS: observe(s,name,{f"bin.{name}"})
    assert choose_next(s) in SCENARIOS

def test_duplicate_bins_across_scenarios_do_not_reward_twice():
    s=default_state(); assert observe(s,"mixed",{"shared","m1"})==2; assert observe(s,"errors",{"shared","e1"})==1; assert set(s["global_bins"])=={"shared","m1","e1"}

def test_ucb_prefers_higher_mean_after_initial_exploration():
    s=default_state()
    for name in SCENARIOS: observe(s,name,{f"init.{name}"})
    observe(s,"mixed",{"m2","m3","m4","m5"}); assert choose_next(s,exploration=0.0)=="mixed"

def test_state_round_count_matches_observations():
    s=default_state(); observe(s,"mixed",{"a"}); observe(s,"boundary",{"b"}); observe(s,"errors",{"c"})
    assert s["rounds"]==3; assert sum(v["pulls"] for v in s["scenarios"].values())==3
