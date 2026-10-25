extends CanvasLayer

signal continued

const Story = preload("res://scripts/story.gd")

@onready var heading: Label = $Overlay/Card/VBox/Heading
@onready var body: Label = $Overlay/Card/VBox/Body
@onready var continue_button: Button = $Overlay/Card/VBox/ContinueButton

func _ready() -> void:
	hide()
	continue_button.pressed.connect(_continue)

func show_chapter(index: int, outro := false) -> void:
	if index < 0 or index >= Story.CHAPTERS.size():
		return
	var chapter: Dictionary = Story.CHAPTERS[index]
	heading.text = chapter.title
	body.text = chapter.outro if outro else chapter.intro
	continue_button.text = "Continuar"
	show()
	continue_button.grab_focus()

func show_prologue() -> void:
	heading.text = "El Reloj Semilla"
	body.text = Story.PROLOGUE
	continue_button.text = "Comenzar"
	show()
	continue_button.grab_focus()

func show_epilogue() -> void:
	heading.text = "Un valle en movimiento"
	body.text = Story.EPILOGUE
	continue_button.text = "Volver al menú"
	show()
	continue_button.grab_focus()

func _continue() -> void:
	hide()
	continued.emit()
