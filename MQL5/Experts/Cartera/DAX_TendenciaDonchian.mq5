//+------------------------------------------------------------------+
//| DAX_TendenciaDonchian.mq5                                        |
//| Seguimiento de tendencia de varios días: entra al romper el      |
//| canal de Donchian, sale por el canal corto o por stop dinámico.  |
//| Pensado para GER40 en H1; sirve para cualquier activo.           |
//| Todas las horas son del servidor.                                |
//+------------------------------------------------------------------+
#property copyright   "fran10101"
#property version     "1.00"
#property description "Tendencia con canal de Donchian (DAX). Horas del servidor."

#include <Cartera\Comun.mqh>

input group "General"
input long           InpMagic         = 730301;
input double         InpRiesgo        = 250.0;     // Riesgo por operación (divisa de la cuenta)
input double         InpMaxPerdidaDia = 0.0;       // Tope de pérdida diaria del EA (0 = sin tope)
input ENUM_DIRECCION InpDireccion     = DIR_AMBAS;

input group "Señal"
input ENUM_TIMEFRAMES InpMarco         = PERIOD_H1;
input int             InpCanalEntrada  = 20;    // Velas del canal de entrada
input int             InpCanalSalida   = 10;    // Velas del canal de salida
input int             InpPeriodoMedia  = 0;     // Filtro: largos solo sobre la SMA y cortos solo debajo (0 = sin filtro)
input int             InpEntradasIniHora = 9;   // Ventana de entradas: hora inicial
input int             InpEntradasFinHora = 21;  // Ventana de entradas: hora final, no incluida

input group "Riesgo y salidas"
input int    InpPeriodoATR   = 20;
input double InpStopATR      = 2.0;    // Stop inicial en ATR
input double InpTrailingATR  = 3.0;    // Stop dinámico en ATR desde el cierre (0 = sin stop dinámico)
input bool   InpCerrarViernes= false;  // Cerrar antes del fin de semana
input int    InpViernesHora  = 22;     // Hora de cierre del viernes

CTrade      trade;
CTopeDiario tope;
int         hATR=INVALID_HANDLE;
int         hMedia=INVALID_HANDLE;
datetime    gUltimaBarra=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpCanalEntrada<2 || InpCanalSalida<2 || InpEntradasIniHora>=InpEntradasFinHora)
     {
      Print("Parámetros incoherentes");
      return INIT_PARAMETERS_INCORRECT;
     }
   hATR=iATR(_Symbol,InpMarco,InpPeriodoATR);
   if(hATR==INVALID_HANDLE)
      return INIT_FAILED;
   if(InpPeriodoMedia>0)
     {
      hMedia=iMA(_Symbol,InpMarco,InpPeriodoMedia,0,MODE_SMA,PRICE_CLOSE);
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
void OnTick()
  {
   if(tope.Bloqueado(trade,_Symbol,InpMagic))
      return;

   datetime ahora =TimeCurrent();
   int      minuto=MinutoDelDia(ahora);
   bool     finDeSemana=InpCerrarViernes && DiaDeLaSemana(ahora)==5 && minuto>=InpViernesHora*60;
   if(finDeSemana)
     {
      CerrarPosiciones(trade,_Symbol,InpMagic);
      return;
     }

   if(!NuevaBarra(_Symbol,InpMarco,gUltimaBarra))
      return;

   double atr=ValorIndicador(hATR,0,1);
   if(atr==EMPTY_VALUE || atr<=0.0)
      return;

   int iTecho      =iHighest(_Symbol,InpMarco,MODE_HIGH,InpCanalEntrada,2);
   int iSuelo      =iLowest(_Symbol,InpMarco,MODE_LOW,InpCanalEntrada,2);
   int iTechoSalida=iHighest(_Symbol,InpMarco,MODE_HIGH,InpCanalSalida,2);
   int iSueloSalida=iLowest(_Symbol,InpMarco,MODE_LOW,InpCanalSalida,2);
   if(iTecho<0 || iSuelo<0 || iTechoSalida<0 || iSueloSalida<0)
      return;
   double techo      =iHigh(_Symbol,InpMarco,iTecho);
   double suelo      =iLow(_Symbol,InpMarco,iSuelo);
   double techoSalida=iHigh(_Symbol,InpMarco,iTechoSalida);
   double sueloSalida=iLow(_Symbol,InpMarco,iSueloSalida);
   double c1=iClose(_Symbol,InpMarco,1);

   bool senalLarga=c1>techo && PermiteLargos(InpDireccion);
   bool senalCorta=c1<suelo && PermiteCortos(InpDireccion);
   if(hMedia!=INVALID_HANDLE)
     {
      double media=ValorIndicador(hMedia,0,1);
      if(media==EMPTY_VALUE)
         return;
      senalLarga=senalLarga && c1>media;
      senalCorta=senalCorta && c1<media;
     }

   ulong tk=TicketPosicion(_Symbol,InpMagic);
   if(tk!=0)
     {
      bool largo=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      bool salir=largo ? (c1<sueloSalida || senalCorta) : (c1>techoSalida || senalLarga);
      if(salir)
        {
         trade.PositionClose(tk);
         tk=0;
        }
      else
        {
         Arrastrar(tk,largo,c1,atr);
         return;
        }
     }

   if(minuto<InpEntradasIniHora*60 || minuto>=InpEntradasFinHora*60)
      return;
   if(senalLarga)
      Entrar(true,atr);
   else if(senalCorta)
      Entrar(false,atr);
  }

//+------------------------------------------------------------------+
void Arrastrar(const ulong tk,const bool largo,const double cierre,const double atr)
  {
   if(InpTrailingATR<=0.0 || !PositionSelectByTicket(tk))
      return;
   double slActual=PositionGetDouble(POSITION_SL);
   double tp      =PositionGetDouble(POSITION_TP);
   double nuevo   =AjustarPrecio(_Symbol,largo ? cierre-atr*InpTrailingATR : cierre+atr*InpTrailingATR);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   double minDist=DistanciaMinima(_Symbol);
   if(largo && (slActual==0.0 || nuevo>slActual) && tick.bid-nuevo>minDist)
      trade.PositionModify(tk,nuevo,tp);
   else if(!largo && (slActual==0.0 || nuevo<slActual) && nuevo-tick.ask>minDist)
      trade.PositionModify(tk,nuevo,tp);
  }

void Entrar(const bool largo,const double atr)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   double distancia=atr*InpStopATR;
   if(distancia<=0.0 || distancia<DistanciaMinima(_Symbol))
      return;
   double lotes=CalcularLotes(_Symbol,InpRiesgo,distancia);
   if(lotes<=0.0)
     {
      Print("El riesgo no alcanza para el lote mínimo: entrada descartada");
      return;
     }
   double entrada=largo ? tick.ask : tick.bid;
   double sl=AjustarPrecio(_Symbol,largo ? entrada-distancia : entrada+distancia);
   bool ok=largo ? trade.Buy(lotes,_Symbol,0.0,sl,0.0,"Donchian")
                 : trade.Sell(lotes,_Symbol,0.0,sl,0.0,"Donchian");
   if(!ok)
      PrintFormat("Orden rechazada: %u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
