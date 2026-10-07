# EAs base para la ronda 10 (DAX, Nikkei, BTC, gas natural)

Plantillas en MQL5 para minar y optimizar, no para desplegar tal cual. Todas usan el mismo riesgo
fijo por operación (250 por defecto) y tienen un tope de pérdida diaria opcional.

## Instalación

Copia la carpeta `MQL5` sobre la carpeta de datos de MetaTrader 5 (Archivo → Abrir carpeta de datos)
y compila los cinco `.mq5` de `Experts/Cartera` en MetaEditor. Todos dependen de
`Include/Cartera/Comun.mqh`.

## EAs

| EA | Activo / marco | Lógica | Magic |
|---|---|---|---|
| `DAX_RangoApertura` | GER40, M1–M15 | Rango de los primeros N minutos desde la hora indicada; órdenes stop a ambos lados; la que entra cancela la otra; cierre forzado por hora | 730101 |
| `DAX_TendenciaDonchian` | GER40, H1–H4 | Cierre fuera del canal de N velas; salida por el canal corto, por señal contraria o por stop dinámico en ATR | 730301 |
| `Nikkei_RupturaSesionPrevia` | JP225, M15 | Cierre de vela por encima del máximo (o debajo del mínimo) del día o de la franja anterior; stop en ATR o en % de la amplitud | 730201 |
| `BTC_VentanaHoraria` | BTCUSD, cualquiera | Entra a una hora fija, solo los días marcados, y sale tras N horas | 730401 |
| `Gas_InformeEIA` | XNGUSD, M1–M5 | Informe EIA del jueves: entra antes en sentido fijo (modo fijo) o tras los primeros minutos siguiendo o contradiciendo el movimiento (modo reacción); sale N minutos después; filtro de meses y de spread | 730501 |

## Parámetros a optimizar primero

| EA | Parámetros | Rango sugerido |
|---|---|---|
| Rango de apertura | `InpRangoMinutos`, `InpObjetivoR`, `InpTipoStop`, `InpMargen` | 5–30 min · 1–3 R · los 3 tipos · 0–5 |
| Donchian | `InpMarco`, `InpCanalEntrada`, `InpCanalSalida`, `InpTrailingATR` | H1/H2/H4 · 10–60 · 5–30 · 0–4 |
| Ruptura Nikkei | `InpReferencia`, `InpStopATR`, `InpObjetivoR`, `InpAperturaDentro` | D1/franja · 1–3 · 1–3 · sí/no |
| Ventana BTC | `InpHoraEntrada`, `InpHorasDentro`, días, `InpPeriodoMediaD1` | 0–23 · 1–6 · por día · 0/50/100/200 |
| Gas EIA | `InpModo`, `InpSentido`, `InpMinAntes`, `InpMinReaccion`, `InpSeguir`, `InpMinDespues` | ambos · ambos · 15–240 · 1–15 · sí/no · 15–240 |

Optimiza con pocos parámetros a la vez y valida fuera de muestra: estas lógicas tienen poca ventaja
y se sobreajustan fácil.

## Horas

- **DAX, Nikkei y Donchian usan la hora del servidor.** En ICM y Tickmill (GMT+2 en invierno, GMT+3
  con el horario de verano de EE. UU.), la apertura del DAX (09:00 CET) cae a las 10:00 del servidor
  casi todo el año. Las semanas en que EE. UU. y Europa cambian de hora en fechas distintas
  (marzo y finales de octubre) se desplaza una hora; el probador no lo corrige.
- **El de BTC permite trabajar en UTC** (`InpReloj = RELOJ_UTC_NY`), porque los estudios de estacionalidad
  dan las horas en UTC. Calcula el desfase del servidor (+2/+3) con el calendario de verano de EE. UU.
  Si tu broker no sigue esa convención, usa `RELOJ_SERVIDOR`.
- Con los valores por defecto (22:00 UTC, 2 horas) la entrada coincide con la medianoche del servidor
  en invierno, cuando el spread suele abrirse. Compruébalo en tu broker o retrasa la entrada.
- **Gas EIA:** en servidores que cierran con Nueva York, las 10:30 de Nueva York son siempre las 17:30
  del servidor, porque ambos cambian de hora a la vez. Si tu broker usa otra convención, ajusta
  `InpHoraInforme`.

## Límites conocidos

- **No están compilados:** no tengo MetaEditor en este entorno. Lo primero es compilarlos y corregir
  lo que salga.
- **El tope de pérdida diaria es por EA,** no de la cuenta. El tope de la cuenta entera hay que vigilarlo aparte.
- **`DAX_RangoApertura` con `InpUnaPorDia = false`** puede tener a la vez un largo y un corto en cuentas hedging.
- **Si el riesgo no cubre el lote mínimo, el EA no opera.** No sube el riesgo.
- **El EA del gas no conoce los festivos de EE. UU.:** las semanas en que la EIA publica en otro día
  u hora, opera igualmente el jueves a la hora fijada. Ese ruido entra en el backtest.
- **Sentido del modo fijo:** el estudio dice que el rendimiento anual se concentra en los días del
  informe, pero no lo he podido contrastar. Optimiza `InpSentido` en vez de dar por hecho que es largo.
- **Spread del gas en CFD:** en torno al informe se abre mucho. Usa `InpSpreadMax` y prueba con
  spread real, no fijo.
