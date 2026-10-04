//+------------------------------------------------------------------+
//| Comun.mqh                                                        |
//| Utilidades compartidas por los EAs de la cartera:                |
//| tamaño por riesgo, tope de pérdida diaria, horas y posiciones.   |
//+------------------------------------------------------------------+
#ifndef CARTERA_COMUN_MQH
#define CARTERA_COMUN_MQH

#include <Trade\Trade.mqh>

enum ENUM_DIRECCION
  {
   DIR_AMBAS  = 0, // Largos y cortos
   DIR_LARGOS = 1, // Solo largos
   DIR_CORTOS = 2  // Solo cortos
  };

bool PermiteLargos(const ENUM_DIRECCION d) { return d!=DIR_CORTOS; }
bool PermiteCortos(const ENUM_DIRECCION d) { return d!=DIR_LARGOS; }

//--- Precios y volumen ---------------------------------------------

int DecimalesVolumen(double paso)
  {
   int d=0;
   while(paso<1.0-1e-9 && d<8)
     {
      paso*=10.0;
      d++;
     }
   return d;
  }

// Lotes para perder 'riesgo' (divisa de la cuenta) si salta un stop a 'distancia' (en precio).
// Devuelve 0 si ni el lote mínimo cabe en ese riesgo: mejor no operar que arriesgar de más.
double CalcularLotes(const string sym,const double riesgo,const double distancia)
  {
   if(riesgo<=0.0 || distancia<=0.0)
      return 0.0;
   double tamTick =SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double valorTick=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(valorTick<=0.0)
      valorTick=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(tamTick<=0.0 || valorTick<=0.0)
      return 0.0;

   double perdidaPorLote=distancia/tamTick*valorTick;
   double lotes =riesgo/perdidaPorLote;
   double paso  =SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double minimo=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maximo=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(paso>0.0)
      lotes=MathFloor(lotes/paso+1e-9)*paso;
   if(lotes<minimo)
      return 0.0;
   if(lotes>maximo)
      lotes=maximo;
   return NormalizeDouble(lotes,DecimalesVolumen(paso));
  }

double AjustarPrecio(const string sym,double precio)
  {
   double tamTick=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(tamTick>0.0)
      precio=MathRound(precio/tamTick)*tamTick;
   return NormalizeDouble(precio,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
  }

double DistanciaMinima(const string sym)
  {
   return (double)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(sym,SYMBOL_POINT);
  }

double ValorIndicador(const int handle,const int buffer,const int shift)
  {
   double v[];
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,v)!=1)
      return EMPTY_VALUE;
   return v[0];
  }

//--- Tiempo ---------------------------------------------------------

datetime InicioDelDia(const datetime t)
  {
   return (datetime)((long)t-(long)t%86400);
  }

int MinutoDelDia(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return s.hour*60+s.min;
  }

int DiaDeLaSemana(const datetime t)   // 0 = domingo ... 6 = sábado
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return s.day_of_week;
  }

bool NuevaBarra(const string sym,const ENUM_TIMEFRAMES marco,datetime &ultima)
  {
   datetime t=iTime(sym,marco,0);
   if(t==0 || t==ultima)
      return false;
   ultima=t;
   return true;
  }

// n-ésimo domingo (n >= 1) de un mes, a las 00:00
datetime DomingoNumero(const int anio,const int mes,const int n)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year=anio;
   s.mon =mes;
   s.day =1;
   datetime primero=StructToTime(s);
   TimeToStruct(primero,s);
   int dia=1+(7-s.day_of_week)%7+7*(n-1);
   return primero+(dia-1)*86400;
  }

// Desfase del servidor respecto a UTC en brokers que cierran con Nueva York
// (IC Markets, Tickmill...): GMT+3 con el horario de verano de EE. UU., GMT+2 el resto.
int DesfaseServidorNY(const datetime servidor)
  {
   MqlDateTime s;
   TimeToStruct(servidor,s);
   datetime inicio=DomingoNumero(s.year,3,2);
   datetime fin   =DomingoNumero(s.year,11,1);
   return (servidor>=inicio && servidor<fin) ? 3*3600 : 2*3600;
  }

//--- Posiciones y órdenes del EA ------------------------------------

// Ticket de la primera posición del EA (y la deja seleccionada), o 0 si no hay.
ulong TicketPosicion(const string sym,const long magic)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)==sym && PositionGetInteger(POSITION_MAGIC)==magic)
         return tk;
     }
   return 0;
  }

void CerrarPosiciones(CTrade &op,const string sym,const long magic)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)==sym && PositionGetInteger(POSITION_MAGIC)==magic)
         op.PositionClose(tk);
     }
  }

int ContarPendientes(const string sym,const long magic)
  {
   int n=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0)
         continue;
      if(OrderGetString(ORDER_SYMBOL)==sym && OrderGetInteger(ORDER_MAGIC)==magic)
         n++;
     }
   return n;
  }

void BorrarPendientes(CTrade &op,const string sym,const long magic)
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0)
         continue;
      if(OrderGetString(ORDER_SYMBOL)==sym && OrderGetInteger(ORDER_MAGIC)==magic)
         op.OrderDelete(tk);
     }
  }

// Resultado del EA desde 'desde': operaciones cerradas (con swap y comisiones) más lo flotante.
double ResultadoDesde(const string sym,const long magic,const datetime desde)
  {
   double total=0.0;
   if(HistorySelect(desde,TimeCurrent()+86400))
     {
      for(int i=HistoryDealsTotal()-1; i>=0; i--)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==0)
            continue;
         if(HistoryDealGetString(tk,DEAL_SYMBOL)!=sym || HistoryDealGetInteger(tk,DEAL_MAGIC)!=magic)
            continue;
         total+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)
               +HistoryDealGetDouble(tk,DEAL_COMMISSION)+HistoryDealGetDouble(tk,DEAL_FEE);
        }
     }
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)==sym && PositionGetInteger(POSITION_MAGIC)==magic)
         total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

// Entradas del EA desde 'desde'
int EntradasDesde(const string sym,const long magic,const datetime desde)
  {
   int n=0;
   if(!HistorySelect(desde,TimeCurrent()+86400))
      return 0;
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0)
         continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)==sym && HistoryDealGetInteger(tk,DEAL_MAGIC)==magic
         && HistoryDealGetInteger(tk,DEAL_ENTRY)==DEAL_ENTRY_IN)
         n++;
     }
   return n;
  }

//--- Tope de pérdida diaria del EA -----------------------------------
// Al alcanzarlo cierra posiciones y órdenes del EA y no deja operar hasta el día siguiente
// (día del servidor). Es por EA: el tope de la cuenta entera hay que vigilarlo aparte.
class CTopeDiario
  {
private:
   double            m_maximo;
   datetime          m_dia;
   datetime          m_ultimoControl;
   bool              m_bloqueado;

public:
                     CTopeDiario(void) : m_maximo(0.0), m_dia(0), m_ultimoControl(0), m_bloqueado(false) {}

   void              Configurar(const double maximo) { m_maximo=maximo; }

   bool              Bloqueado(CTrade &op,const string sym,const long magic)
     {
      datetime ahora=TimeCurrent();
      datetime dia  =InicioDelDia(ahora);
      if(dia!=m_dia)
        {
         m_dia=dia;
         m_bloqueado=false;
        }
      if(m_bloqueado)
         return true;
      // como mucho un control por segundo: el historial es caro en el probador
      if(m_maximo<=0.0 || ahora==m_ultimoControl)
         return false;
      m_ultimoControl=ahora;
      if(ResultadoDesde(sym,magic,dia)<=-m_maximo)
        {
         CerrarPosiciones(op,sym,magic);
         BorrarPendientes(op,sym,magic);
         m_bloqueado=true;
         PrintFormat("Tope diario de %.2f alcanzado: sin operar hasta mañana",m_maximo);
        }
      return m_bloqueado;
     }
  };

#endif
//+------------------------------------------------------------------+
