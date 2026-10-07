//+------------------------------------------------------------------+
//| Gas_InformeEIA.mq5                                               |
//| Opera en torno al informe semanal de almacenamiento de gas de    |
//| la EIA (jueves 10:30 hora de Nueva York).                        |
//|  - Modo fijo: entra N minutos antes del informe en el sentido    |
//|    elegido y sale M minutos después.                             |
//|  - Modo reacción: mide el movimiento de los primeros minutos     |
//|    tras el informe y lo sigue (o lo contradice).                 |
//| Todas las horas son del servidor.                                |
//+------------------------------------------------------------------+
#property copyright   "fran10101"
#property version     "1.00"
#property description "Informe EIA del gas natural. Horas del servidor."

#include <Cartera\Comun.mqh>

enum ENUM_MODO_EIA
  {
   MODO_FIJO     = 0, // Entrada antes del informe en sentido fijo
   MODO_REACCION = 1  // Entrada tras el informe según su primer movimiento
  };

enum ENUM_SENTIDO_EIA
  {
   EIA_LARGO = 0, // Largo
   EIA_CORTO = 1  // Corto
  };

input group "General"
input long   InpMagic         = 730501;
input double InpRiesgo        = 250.0;     // Riesgo por operación (divisa de la cuenta)
input double InpMaxPerdidaDia = 0.0;       // Tope de pérdida diaria del EA (0 = sin tope)

input group "Informe (hora del servidor)"
input int    InpDiaInforme    = 4;     // Día del informe (0 = domingo ... 4 = jueves)
input int    InpHoraInforme   = 17;    // 10:30 en Nueva York = 17:30 en servidores GMT+2/+3 que cierran con NY
input int    InpMinutoInforme = 30;
input string InpMeses         = "";    // Meses en que opera, p. ej. "9,10,11" (vacío = todos)

input group "Entrada"
input ENUM_MODO_EIA    InpModo            = MODO_FIJO;
input ENUM_SENTIDO_EIA InpSentido         = EIA_LARGO;  // Modo fijo: sentido de la entrada
input int              InpMinAntes        = 60;         // Modo fijo: minutos antes del informe
input int              InpMinReaccion     = 5;          // Modo reacción: minutos tras el informe para medir
input double           InpMovimientoMin   = 0.0;        // Modo reacción: movimiento mínimo, en precio
input bool             InpSeguir          = true;       // Modo reacción: true = seguir el movimiento, false = ir en contra
input int              InpMinutosMargen   = 5;          // Minutos tras la hora prevista en los que aún se puede entrar
input double           InpSpreadMax       = 0.0;        // Spread máximo para entrar, en precio (0 = sin filtro)

input group "Salidas"
input int    InpMinDespues  = 60;    // Cierre: minutos después del informe
input int    InpPeriodoATR  = 24;    // ATR en H1, para el stop
input double InpStopATR     = 1.5;   // Stop en ATR de H1
input double InpObjetivoR   = 0.0;   // Objetivo en R (0 = sale por tiempo)

CTrade      trade;
CTopeDiario tope;
int         hATR=INVALID_HANDLE;
datetime    gUltimoDia=0;
bool        gMeses[13];

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpDiaInforme<0 || InpDiaInforme>6 || InpHoraInforme<0 || InpHoraInforme>23
      || InpMinutoInforme<0 || InpMinutoInforme>59 || InpMinutosMargen<1)
     {
      Print("Hora del informe incoherente");
      return INIT_PARAMETERS_INCORRECT;
     }
   int informe=InpHoraInforme*60+InpMinutoInforme;
   int entrada=(InpModo==MODO_FIJO) ? informe-InpMinAntes : informe+InpMinReaccion;
   int salida =informe+InpMinDespues;
   if(InpMinAntes<0 || InpMinReaccion<1 || entrada<0 || entrada+InpMinutosMargen>salida || salida>=24*60)
     {
      Print("Horario incoherente: la entrada debe quedar antes de la salida y dentro del mismo día");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!LeerMeses())
      return INIT_PARAMETERS_INCORRECT;

   hATR=iATR(_Symbol,PERIOD_H1,InpPeriodoATR);
   if(hATR==INVALID_HANDLE)
      return INIT_FAILED;
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

bool LeerMeses()
  {
   bool todos=(StringLen(InpMeses)==0);
   for(int m=1; m<=12; m++)
      gMeses[m]=todos;
   if(todos)
      return true;
   string partes[];
   int n=StringSplit(InpMeses,',',partes);
   for(int i=0; i<n; i++)
     {
      int m=(int)StringToInteger(partes[i]);
      if(m<1 || m>12)
        {
         PrintFormat("Mes no válido en InpMeses: '%s'",partes[i]);
         return false;
        }
      gMeses[m]=true;
     }
   return true;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(tope.Bloqueado(trade,_Symbol,InpMagic))
      return;

   datetime ahora  =TimeCurrent();
   int      informe=InpHoraInforme*60+InpMinutoInforme;

   ulong tk=TicketPosicion(_Symbol,InpMagic);
   if(tk!=0)
     {
      datetime apertura=(datetime)PositionGetInteger(POSITION_TIME);
      if(ahora>=InicioDelDia(apertura)+(informe+InpMinDespues)*60)
         trade.PositionClose(tk);
      return;
     }

   datetime dia=InicioDelDia(ahora);
   if(dia==gUltimoDia || DiaDeLaSemana(ahora)!=InpDiaInforme)
      return;
   MqlDateTime s;
   TimeToStruct(ahora,s);
   if(!gMeses[s.mon])
      return;

   int minuto =MinutoDelDia(ahora);
   int entrada=(InpModo==MODO_FIJO) ? informe-InpMinAntes : informe+InpMinReaccion;
   if(minuto<entrada || minuto>=entrada+InpMinutosMargen)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   if(InpSpreadMax>0.0 && tick.ask-tick.bid>InpSpreadMax)
      return;   // se reintenta mientras dure el margen de entrada

   gUltimoDia=dia;   // un solo intento por informe
   if(InpModo==MODO_FIJO)
     {
      Entrar(InpSentido==EIA_LARGO,tick);
      return;
     }

   // precio de referencia: apertura de la vela M1 del informe
   datetime tInforme=dia+informe*60;
   int barra=iBarShift(_Symbol,PERIOD_M1,tInforme,true);
   if(barra<0)
      return;
   double movimiento=tick.bid-iOpen(_Symbol,PERIOD_M1,barra);
   if(movimiento==0.0 || MathAbs(movimiento)<InpMovimientoMin)
      return;
   bool sube=(movimiento>0.0);
   Entrar(InpSeguir ? sube : !sube,tick);
  }

void Entrar(const bool largo,const MqlTick &tick)
  {
   double atr=ValorIndicador(hATR,0,1);
   if(atr==EMPTY_VALUE || atr<=0.0)
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
   bool ok=largo ? trade.Buy(lotes,_Symbol,0.0,sl,tp,"EIA")
                 : trade.Sell(lotes,_Symbol,0.0,sl,tp,"EIA");
   if(!ok)
      PrintFormat("Orden rechazada: %u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
