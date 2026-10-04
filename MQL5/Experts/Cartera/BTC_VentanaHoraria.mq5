//+------------------------------------------------------------------+
//| BTC_VentanaHoraria.mq5                                           |
//| Estacionalidad intradía: entra a una hora fija y sale tras N     |
//| horas, solo los días elegidos. Cierra en el día: no paga swap    |
//| nocturno salvo que la ventana cruce la hora del rollover.        |
//+------------------------------------------------------------------+
#property copyright   "fran10101"
#property version     "1.00"
#property description "Ventana horaria en BTC. Horas en UTC o del servidor."

#include <Cartera\Comun.mqh>

enum ENUM_RELOJ
  {
   RELOJ_SERVIDOR = 0, // Horas y días del servidor
   RELOJ_UTC_NY   = 1  // Horas y días en UTC (servidor GMT+2/+3 que cierra con Nueva York)
  };

enum ENUM_SENTIDO
  {
   SENTIDO_LARGO = 0, // Largo
   SENTIDO_CORTO = 1  // Corto
  };

input group "General"
input long         InpMagic         = 730401;
input double       InpRiesgo        = 250.0;     // Riesgo por operación (divisa de la cuenta)
input double       InpMaxPerdidaDia = 0.0;       // Tope de pérdida diaria del EA (0 = sin tope)
input ENUM_SENTIDO InpSentido       = SENTIDO_LARGO;

input group "Ventana"
input ENUM_RELOJ InpReloj          = RELOJ_UTC_NY;
input int        InpHoraEntrada    = 22;   // Hora de entrada
input int        InpMinutoEntrada  = 0;    // Minuto de entrada
input int        InpMinutosMargen  = 10;   // Minutos tras la hora en los que aún se puede entrar
input int        InpHorasDentro    = 2;    // Horas que se mantiene la posición
input bool       InpLunes          = true;
input bool       InpMartes         = true;
input bool       InpMiercoles      = true;
input bool       InpJueves         = true;
input bool       InpViernes        = true;
input bool       InpSabado         = false;
input bool       InpDomingo        = true;

input group "Riesgo y filtro"
input int    InpPeriodoATR    = 24;    // ATR en H1, solo para dimensionar el stop
input double InpStopATR       = 2.0;   // Stop en ATR de H1
input double InpObjetivoR     = 0.0;   // Objetivo en R (0 = sale por tiempo)
input int    InpPeriodoMediaD1= 0;     // Filtro: largos solo sobre la SMA diaria y cortos solo debajo (0 = sin filtro)

CTrade      trade;
CTopeDiario tope;
int         hATR=INVALID_HANDLE;
int         hMedia=INVALID_HANDLE;
datetime    gUltimaFranja=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpHoraEntrada<0 || InpHoraEntrada>23 || InpMinutoEntrada<0 || InpMinutoEntrada>59
      || InpHorasDentro<1 || InpMinutosMargen<1)
     {
      Print("Parámetros de ventana incoherentes");
      return INIT_PARAMETERS_INCORRECT;
     }
   hATR=iATR(_Symbol,PERIOD_H1,InpPeriodoATR);
   if(hATR==INVALID_HANDLE)
      return INIT_FAILED;
   if(InpPeriodoMediaD1>0)
     {
      hMedia=iMA(_Symbol,PERIOD_D1,InpPeriodoMediaD1,0,MODE_SMA,PRICE_CLOSE);
      if(hMedia==INVALID_HANDLE)
         return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   tope.Configurar(InpMaxPerdidaDia);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(hATR!=INVALID_HANDLE)
      IndicatorRelease(hATR);
   if(hMedia!=INVALID_HANDLE)
      IndicatorRelease(hMedia);
  }

//+------------------------------------------------------------------+
datetime HoraDelReloj(const datetime servidor)
  {
   return InpReloj==RELOJ_UTC_NY ? servidor-DesfaseServidorNY(servidor) : servidor;
  }

bool DiaPermitido(const datetime t)
  {
   switch(DiaDeLaSemana(t))
     {
      case 0:  return InpDomingo;
      case 1:  return InpLunes;
      case 2:  return InpMartes;
      case 3:  return InpMiercoles;
      case 4:  return InpJueves;
      case 5:  return InpViernes;
      default: return InpSabado;
     }
  }

void OnTick()
  {
   if(tope.Bloqueado(trade,_Symbol,InpMagic))
      return;

   datetime ahora=TimeCurrent();
   ulong tk=TicketPosicion(_Symbol,InpMagic);
   if(tk!=0)
     {
      datetime apertura=(datetime)PositionGetInteger(POSITION_TIME);
      if(ahora>=apertura+InpHorasDentro*3600)
         trade.PositionClose(tk);
      return;
     }

   datetime reloj  =HoraDelReloj(ahora);
   int      minuto =MinutoDelDia(reloj);
   int      entrada=InpHoraEntrada*60+InpMinutoEntrada;
   if(minuto<entrada || minuto>=entrada+InpMinutosMargen)
      return;
   datetime franja=InicioDelDia(reloj)+entrada*60;
   if(franja==gUltimaFranja || !DiaPermitido(reloj))
      return;
   gUltimaFranja=franja;   // un solo intento por franja

   bool largo=(InpSentido==SENTIDO_LARGO);
   if(hMedia!=INVALID_HANDLE)
     {
      double media=ValorIndicador(hMedia,0,1);
      double c1   =iClose(_Symbol,PERIOD_D1,1);
      if(media==EMPTY_VALUE || c1<=0.0 || (largo && c1<=media) || (!largo && c1>=media))
         return;
     }
   Entrar(largo);
  }

void Entrar(const bool largo)
  {
   double atr=ValorIndicador(hATR,0,1);
   if(atr==EMPTY_VALUE || atr<=0.0)
      return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   double distancia=atr*InpStopATR;
   if(distancia<DistanciaMinima(_Symbol))
      return;
   double lotes=CalcularLotes(_Symbol,InpRiesgo,distancia);
   if(lotes<=0.0)
     {
      Print("El riesgo no alcanza para el lote mínimo: entrada descartada");
      return;
     }
   double precio=largo ? tick.ask : tick.bid;
   double sl=AjustarPrecio(_Symbol,largo ? precio-distancia : precio+distancia);
   double tp=0.0;
   if(InpObjetivoR>0.0)
      tp=AjustarPrecio(_Symbol,largo ? precio+distancia*InpObjetivoR : precio-distancia*InpObjetivoR);
   bool ok=largo ? trade.Buy(lotes,_Symbol,0.0,sl,tp,"VentanaBTC")
                 : trade.Sell(lotes,_Symbol,0.0,sl,tp,"VentanaBTC");
   if(!ok)
      PrintFormat("Orden rechazada: %u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
