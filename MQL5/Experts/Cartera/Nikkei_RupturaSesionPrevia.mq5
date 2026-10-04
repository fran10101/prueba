//+------------------------------------------------------------------+
//| Nikkei_RupturaSesionPrevia.mq5                                   |
//| Ruptura del máximo o mínimo de la sesión anterior, al cierre     |
//| de vela (M15 por defecto), en largo y en corto.                  |
//| Pensado para JP225; sirve para cualquier índice.                 |
//| Todas las horas son del servidor.                                |
//+------------------------------------------------------------------+
#property copyright   "fran10101"
#property version     "1.00"
#property description "Ruptura de la sesión anterior (Nikkei). Horas del servidor."

#include <Cartera\Comun.mqh>

enum ENUM_REFERENCIA
  {
   REF_D1     = 0, // Máximo y mínimo de la vela D1 anterior
   REF_SESION = 1  // Máximo y mínimo de una franja horaria del día anterior
  };

enum ENUM_STOP_RUPTURA
  {
   STOPR_ATR   = 0, // Múltiplo del ATR
   STOPR_RANGO = 1  // Porcentaje de la amplitud de la referencia
  };

input group "General"
input long           InpMagic         = 730201;
input double         InpRiesgo        = 250.0;     // Riesgo por operación (divisa de la cuenta)
input double         InpMaxPerdidaDia = 0.0;       // Tope de pérdida diaria del EA (0 = sin tope)
input ENUM_DIRECCION InpDireccion     = DIR_AMBAS;

input group "Señal"
input ENUM_TIMEFRAMES InpMarco          = PERIOD_M15;
input ENUM_REFERENCIA InpReferencia     = REF_D1;
input int             InpSesionIniHora  = 2;     // Franja de referencia: hora inicial (si REF_SESION)
input int             InpSesionFinHora  = 9;     // Franja de referencia: hora final, no incluida
input double          InpMargen         = 0.0;   // Margen sobre el nivel, en precio
input bool            InpAperturaDentro = true;  // Solo si el día abre dentro del rango de referencia
input int             InpMaxEntradasDia = 1;     // Entradas máximas por día
input int             InpEntradasIniHora= 3;     // Ventana de entradas: hora inicial
input int             InpEntradasFinHora= 20;    // Ventana de entradas: hora final, no incluida

input group "Salidas"
input ENUM_STOP_RUPTURA InpTipoStop     = STOPR_ATR;
input double            InpStopATR      = 1.5;   // Multiplicador del ATR (si el stop es ATR)
input int               InpPeriodoATR   = 14;    // Periodo del ATR (en el marco de la señal)
input double            InpStopPctRango = 50.0;  // % de la amplitud de la referencia (si el stop es rango)
input double            InpObjetivoR    = 2.0;   // Objetivo en R (0 = sin objetivo)
input bool              InpCerrarFinDia = true;  // Cerrar a la hora de cierre
input int               InpCierreHora   = 22;
input int               InpCierreMin    = 45;

CTrade      trade;
CTopeDiario tope;
int         hATR=INVALID_HANDLE;
datetime    gUltimaBarra=0;
datetime    gDia=0;
bool        gReferenciaLista=false;
double      gAlto=0.0, gBajo=0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpReferencia==REF_SESION && InpSesionIniHora>=InpSesionFinHora)
     {
      Print("Franja de referencia incoherente");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpEntradasIniHora>=InpEntradasFinHora || InpMaxEntradasDia<1)
     {
      Print("Ventana de entradas incoherente");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTipoStop==STOPR_ATR)
     {
      hATR=iATR(_Symbol,InpMarco,InpPeriodoATR);
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

   datetime ahora =TimeCurrent();
   datetime dia   =InicioDelDia(ahora);
   int      minuto=MinutoDelDia(ahora);

   if(dia!=gDia)
     {
      gDia=dia;
      gReferenciaLista=false;
     }

   if(InpCerrarFinDia && minuto>=InpCierreHora*60+InpCierreMin)
     {
      CerrarPosiciones(trade,_Symbol,InpMagic);
      return;
     }

   if(!NuevaBarra(_Symbol,InpMarco,gUltimaBarra))
      return;
   if(!gReferenciaLista)
      gReferenciaLista=CalcularReferencia(dia);
   if(!gReferenciaLista || gAlto<=gBajo)
      return;

   if(minuto<InpEntradasIniHora*60 || minuto>=InpEntradasFinHora*60)
      return;
   if(TicketPosicion(_Symbol,InpMagic)!=0)
      return;
   if(EntradasDesde(_Symbol,InpMagic,dia)>=InpMaxEntradasDia)
      return;
   if(InpAperturaDentro)
     {
      double apertura=iOpen(_Symbol,PERIOD_D1,0);
      if(apertura>gAlto || apertura<gBajo)
         return;
     }

   double c1=iClose(_Symbol,InpMarco,1);
   double c2=iClose(_Symbol,InpMarco,2);
   double nivelAlto=gAlto+InpMargen;
   double nivelBajo=gBajo-InpMargen;

   if(PermiteLargos(InpDireccion) && c1>nivelAlto && c2<=nivelAlto)
      Entrar(true);
   else if(PermiteCortos(InpDireccion) && c1<nivelBajo && c2>=nivelBajo)
      Entrar(false);
  }

//+------------------------------------------------------------------+
bool CalcularReferencia(const datetime dia)
  {
   if(InpReferencia==REF_D1)
     {
      gAlto=iHigh(_Symbol,PERIOD_D1,1);
      gBajo=iLow(_Symbol,PERIOD_D1,1);
      return gAlto>0.0 && gBajo>0.0;
     }
   datetime diaAnterior=iTime(_Symbol,PERIOD_D1,1);
   if(diaAnterior==0 || diaAnterior>=dia)
      return false;
   datetime t0=diaAnterior+InpSesionIniHora*3600;
   datetime t1=diaAnterior+InpSesionFinHora*3600-1;
   double altos[],bajos[];
   int n=CopyHigh(_Symbol,PERIOD_M5,t0,t1,altos);
   if(n<=0 || CopyLow(_Symbol,PERIOD_M5,t0,t1,bajos)!=n)
      return false;
   gAlto=altos[ArrayMaximum(altos)];
   gBajo=bajos[ArrayMinimum(bajos)];
   return true;
  }

void Entrar(const bool largo)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   double entrada=largo ? tick.ask : tick.bid;

   double distancia;
   if(InpTipoStop==STOPR_ATR)
     {
      double atr=ValorIndicador(hATR,0,1);
      if(atr==EMPTY_VALUE || atr<=0.0)
         return;
      distancia=atr*InpStopATR;
     }
   else
      distancia=(gAlto-gBajo)*InpStopPctRango/100.0;
   if(distancia<=0.0 || distancia<DistanciaMinima(_Symbol))
      return;

   double lotes=CalcularLotes(_Symbol,InpRiesgo,distancia);
   if(lotes<=0.0)
     {
      Print("El riesgo no alcanza para el lote mínimo: entrada descartada");
      return;
     }
   double sl=AjustarPrecio(_Symbol,largo ? entrada-distancia : entrada+distancia);
   double tp=0.0;
   if(InpObjetivoR>0.0)
      tp=AjustarPrecio(_Symbol,largo ? entrada+distancia*InpObjetivoR : entrada-distancia*InpObjetivoR);

   bool ok=largo ? trade.Buy(lotes,_Symbol,0.0,sl,tp,"RupturaPrevia")
                 : trade.Sell(lotes,_Symbol,0.0,sl,tp,"RupturaPrevia");
   if(!ok)
      PrintFormat("Orden rechazada: %u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
