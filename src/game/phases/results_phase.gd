class_name ResultsPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null

func setup(p_session: Session, p_fsm: GameStateMachine) -> void:
	session = p_session
	fsm = p_fsm
