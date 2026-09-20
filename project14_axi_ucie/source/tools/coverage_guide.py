#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path
from typing import Iterable, List, Set
SCENARIOS: List[str] = ["mixed","boundary","errors","partial_strobe","latency","read_heavy","write_heavy"]

def default_state() -> dict:
    return {"global_bins":[],"rounds":0,"scenarios":{n:{"pulls":0,"reward_sum":0.0,"last_reward":0.0} for n in SCENARIOS}}

def load_state(path: Path) -> dict:
    if not path.exists(): return default_state()
    state=json.loads(path.read_text())
    for s in SCENARIOS: state.setdefault("scenarios",{}).setdefault(s,{"pulls":0,"reward_sum":0.0,"last_reward":0.0})
    state.setdefault("global_bins",[]); state.setdefault("rounds",0)
    return state

def save_state(path: Path,state: dict)->None:
    path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(state,indent=2,sort_keys=True)+"\n")

def read_bins(path: Path)->Set[str]:
    if not path.exists(): raise FileNotFoundError(f"coverage-bin file not found: {path}")
    return {line.strip() for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")}

def observe(state: dict,scenario: str,bins: Iterable[str])->int:
    if scenario not in state["scenarios"]: raise ValueError(f"unknown scenario: {scenario}")
    global_bins=set(state["global_bins"]); run_bins=set(bins); new_bins=run_bins-global_bins; reward=len(new_bins)
    st=state["scenarios"][scenario]; st["pulls"]+=1; st["reward_sum"]+=float(reward); st["last_reward"]=float(reward)
    state["rounds"]+=1; state["global_bins"]=sorted(global_bins|run_bins); return reward

def choose_next(state: dict,exploration: float=1.4)->str:
    for s in SCENARIOS:
        if state["scenarios"][s]["pulls"]==0: return s
    total=max(1,sum(v["pulls"] for v in state["scenarios"].values()))
    best_s=SCENARIOS[0]; best_score=float("-inf")
    for s in SCENARIOS:
        st=state["scenarios"][s]; mean=st["reward_sum"]/st["pulls"]; bonus=exploration*math.sqrt(math.log(total)/st["pulls"]); score=mean+bonus
        if score>best_score: best_score=score; best_s=s
    return best_s
