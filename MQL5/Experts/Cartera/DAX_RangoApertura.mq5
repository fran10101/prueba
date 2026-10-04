//+------------------------------------------------------------------+
//| DAX_RangoApertura.mq5                                            |
//| Ruptura del rango de apertura con dos órdenes stop (OCO).        |
//| Pensado para GER40 en M1/M5; sirve para cualquier índice.        |
//| Todas las horas son del servidor.                                |
//+------------------------------------------------------------------+
#property copyright   "fran10101"
#property version     "1.00"
#property description "Ruptura del rango de apertura (DAX). Horas del servidor."

#include <Cartera\Comun.mqh>

enum ENUM_STOP_ORB
  {
   STOP_RANGO_OPUESTO = 0, // Lado opuesto del rango
   STOP_MITAD_RANGO   = 1, // Mitad del rango
   STOP_ATR           = 2  // Múltiplo del ATR (M15)
  };

input group "General"
input long           InpMagic         = 730101;
input double         InpRiesgo        = 250.0;     // Riesgo por operación (divisa de la cuenta)
input double         InpMaxPerdidaDia = 0.0;       // Tope de pérdida diaria del EA (0 = sin tope)
input ENUM_DIRECCION InpDireccion     = DIR_AMBAS;

input group "Rango (hora del servidor)"
input int    InpRangoHora    = 10;    // Inicio del rango: hora (09:00 CET = 10:00 en servidores GMT+2/+3)
input int    InpRangoMinuto  = 0;     // Inicio del rango: minuto
input int    InpRangoMinutos = 15;    // Duración del rango (minutos)
input double InpRangoMin     = 0.0;   // Amplitud mínima del rango, en precio (0 = sin filtro)
input double InpRangoMax     = 0.0;   // Amplitud máxima del rango, en precio (0 = sin filtro)
input double InpMargen       = 2.0;   // Margen sobre el rango para la orden stop, en precio

input group "Salidas"
input ENUM_STOP_ORB InpTipoStop        = STOP_RANGO_OPUESTO;
input double        InpStopATR         = 1.0;   // Multiplicador del ATR (si el stop es ATR)
input int           InpPeriodoATR      = 14;    // Periodo del ATR (M15)
input double        InpObjetivoR       = 2.0;   // Objetivo en R (0 = sin objetivo, sale por hora)
input int           InpFinEntradasHora = 13;    // Hora límite para que entre la orden
input int           InpFinEntradasMin  = 0;
input int           InpCierreHora      = 21;    // Cierre forzado: hora
input int           InpCierreMin       = 30;    // Cierre forzado: minuto
input bool          InpUnaPorDia       = true;  // Al entrar, cancelar la orden contraria

CTrade      trade;
CTopeDiario tope;
int         hATR=INVALID_HANDLE;
datetime    gDia=0;
bool        gOrdenesPuestas=false;

//+------------------------------------------------------------------+
int OnInit()
  {
   int finRango   =InpRangoHora*60+InpRangoMinuto+InpRangoMinutos;
   int finEntradas=InpFinEntradasHora*60+InpFinEntradasMin;
   int cierre     =InpCierreHora*60+InpCierreMin;
   if(InpRangoMinutos<=0 || finRango>=finEntradas || finEntradas>cierre || cierre>24*60)
     {
      Print("Horario incoherente: debe cumplirse fin del rango < fin de entradas <= cierre");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTipoStop==STOP_ATR)
     {
      hATR=iATR(_Symbol,PERIOD_M15,InpPeriodoATR);
      if(hATR==INVALID_HANDLE)
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
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(tope.Bloqueado(trade,_Symbol,InpMagic))
      return;

   datetime ahora=TimeCurrent();
   datetime dia  =InicioDelDia(ahora);
   if(dia!=gDia)
     {
      gDia=dia;
      gOrdenesPuestas=false;
     }

   int minuto     =MinutoDelDia(ahora);
   int finRango   =InpRangoHora*60+InpRangoMinuto+InpRangoMinutos;
   int finEntradas=InpFinEntradasHora*60+InpFinEntradasMin;
   int cierre     =InpCierreHora*60+InpCierreMin;

   if(minuto>=cierre)
     {
      CerrarPosiciones(trade,_Symbol,InpMagic);
      BorrarPendientes(trade,_Symbol,InpMagic);
      return;
     }

   if(ContarPendientes(_Symbol,InpMagic)>0)
     {
      if(minuto>=finEntradas || (InpUnaPorDia && TicketPosicion(_Symbol,InpMagic)!=0))
         BorrarPendientes(trade,_Symbol,InpMagic);
     }

   if(!gOrdenesPuestas && minuto>=finRango && minuto<finEntradas)
      gOrdenesPuestas=ColocarOrdenes(dia);
  }

//+------------------------------------------------------------------+
// Devuelve false solo si aún no hay datos del rango (se reintenta en el siguiente tick)
bool ColocarOrdenes(const datetime dia)
  {
   datetime t0=dia+InpRangoHora*3600+InpRangoMinuto*60;
   datetime t1=t0+InpRangoMinutos*60-1;
   double altos[],bajos[];
   int n=CopyHigh(_Symbol,PERIOD_M1,t0,t1,altos);
   if(n<=0 || CopyLow(_Symbol,PERIOD_M1,t0,t1,bajos)!=n)
      return false;

   double maximo  =altos[ArrayMaximum(altos)];
   double minimo  =bajos[ArrayMinimum(bajos)];
   double amplitud=maximo-minimo;
   if(amplitud<=0.0 || (InpRangoMin>0.0 && amplitud<InpRangoMin) || (InpRangoMax>0.0 && amplitud>InpRangoMax))
      return true;   // día filtrado

   double atr=0.0;
   if(InpTipoStop==STOP_ATR)
     {
      atr=ValorIndicador(hATR,0,1);
      if(atr==EMPTY_VALUE || atr<=0.0)
         return true;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   double minDist=DistanciaMinima(_Symbol);

   // si el precio ya ha roto el rango, ese lado se pierde: no se persigue a mercado
   if(PermiteLargos(InpDireccion))
     {
      double entrada=AjustarPrecio(_Symbol,maximo+InpMargen);
      double sl;
      switch(InpTipoStop)
        {
         case STOP_RANGO_OPUESTO: sl=minimo-InpMargen;          break;
         case STOP_MITAD_RANGO:   sl=(maximo+minimo)/2.0;       break;
         default:                 sl=entrada-atr*InpStopATR;    break;
        }
      if(entrada-tick.ask>minDist)
         ColocarStop(ORDER_TYPE_BUY_STOP,entrada,AjustarPrecio(_Symbol,sl));
     }
   if(PermiteCortos(InpDireccion))
     {
      double entrada=AjustarPrecio(_Symbol,minimo-InpMargen);
      double sl;
      switch(InpTipoStop)
        {
         case STOP_RANGO_OPUESTO: sl=maximo+InpMargen;          break;
         case STOP_MITAD_RANGO:   sl=(maximo+minimo)/2.0;       break;
         default:                 sl=entrada+atr*InpStopATR;    break;
        }
      if(tick.bid-entrada>minDist)
         ColocarStop(ORDER_TYPE_SELL_STOP,entrada,AjustarPrecio(_Symbol,sl));
     }
   return true;
  }

void ColocarStop(const ENUM_ORDER_TYPE tipo,const double entrada,const double sl)
  {
   double distancia=MathAbs(entrada-sl);
   if(distancia<=0.0 || distancia<DistanciaMinima(_Symbol))
      return;
   double lotes=CalcularLotes(_Symbol,InpRiesgo,distancia);
   if(lotes<=0.0)
     {
      Print("El riesgo no alcanza para el lote mínimo: orden no colocada");
      return;
     }
   bool largo=(tipo==ORDER_TYPE_BUY_STOP);
   double tp=0.0;
   if(InpObjetivoR>0.0)
      tp=AjustarPrecio(_Symbol,largo ? entrada+distancia*InpObjetivoR : entrada-distancia*InpObjetivoR);

   bool ok=largo ? trade.BuyStop(lotes,entrada,_Symbol,sl,tp,ORDER_TIME_GTC,0,"ORB")
                 : trade.SellStop(lotes,entrada,_Symbol,sl,tp,ORDER_TIME_GTC,0,"ORB");
   if(!ok)
      PrintFormat("Orden rechazada: %u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
