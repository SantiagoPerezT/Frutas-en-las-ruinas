extends RefCounted

# Story mode uses the same playable levels. Keep dialogue here so the map,
# menu and save code do not have to carry narrative text.
const PROLOGUE := "El Reloj Semilla detuvo las estaciones del valle. Lía, aprendiz de guardiana, debe encontrar sus cuatro engranajes antes de que la última cosecha se marchite."
const EPILOGUE := "Lía devuelve los engranajes al Reloj Semilla. El valle vuelve a cambiar con el tiempo: habrá días de lluvia y frío, pero también nuevas cosechas y caminos por descubrir."

const CHAPTERS: Array[Dictionary] = [
	{
		"title": "Capítulo 1 · Las ruinas del huerto",
		"intro": "Las raíces han abierto la vieja ciudad. Sigue las marcas que dejó la primera guardiana: entre los muros duerme el engranaje de la memoria.",
		"outro": "Lía encuentra el primer engranaje bajo el arco del huerto. Una inscripción señala el bosque, donde los árboles aún recuerdan el camino.",
	},
	{
		"title": "Capítulo 2 · El bosque esmeralda",
		"intro": "El bosque ha crecido sin una sola noche. Sus senderos se repiten como un sueño; las luciérnagas indican la ruta hacia el corazón verde.",
		"outro": "El corazón del bosque entrega el segundo engranaje. Entre sus hojas aparece un mapa de las dunas y una advertencia sobre el fuego inmóvil.",
	},
	{
		"title": "Capítulo 3 · Las dunas del sol",
		"intro": "El sol lleva semanas sobre las dunas. Lía cruza los puentes de piedra para hallar el horno antiguo, donde se forjó el tercer engranaje.",
		"outro": "El horno se enfría y revela el tercer engranaje. El viento vuelve a soplar, llevando un rastro brillante hacia las cumbres de cristal.",
	},
	{
		"title": "Capítulo 4 · Las cumbres de cristal",
		"intro": "La cima guarda la última pieza. Quien detuvo el reloj quería conservar un día perfecto para siempre; Lía debe decidir si el valle merece volver a cambiar.",
		"outro": "Lía recupera el último engranaje. Comprende que proteger el valle también significa permitirle crecer y transformarse.",
	},
]
