//  SINGLE-FILE BUILD  -  no Include/ folder needed.
//
//  Upstream GOLD_ORB.mq5 pulls nine .mqh files from an Include/ folder beside
//  it. They are inlined below, so this compiles on its own.
//
//  Inlined (the author's own, ~2,960 lines): Trade, TradeVirtual,
//  TrailingStops, TrailingStopsVirtual, price_action, Indicators,
//  MoneyManagement, RiskManagement, errordescription. Each appears once even
//  though four files included errordescription.mqh, and each file's own
//  includes are emitted before its body so dependencies precede use.
//
//  #property lines were stripped from the inlined files - every one carried
//  its own copyright/link/version block, and repeating them makes MQL5
//  complain. Only the main file keeps its properties.
//
//  NOT inlined: Include/Math/Stat/Normal.mqh is MetaQuotes' own standard
//  library file that had been bundled into the repo. It now uses MT5's copy
//  via an angle-bracket include; inlining it would add 6,400 lines of
//  MetaQuotes code when the only symbol used from it is MathSum().
//
//  Also carries the braces fix to the equity-drawdown guard, without which
//  enabling that guard stops the EA trading entirely. See PROVENANCE.md.
//----------------------------------------------------------------------

//+------------------------------------------------------------------+
//|                                               MQL5 Practice1.mq5 |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Playground Inc 2021"
#property link      "https://www.mql5.com"
#property version   "1.00"

/* 
Author: Ulysses O. Andulte
Date Created: 10/26/2022
*/


//Include Files

//====================================================================
//  INLINED: Include/Trade.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                        Trade.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+



#ifndef MAX_RETRIES
#define MAX_RETRIES 5  // Max retries on error
#endif
#ifndef RETRY_DELAY
#define RETRY_DELAY 3000 // Retry delay in ms
#endif


//====================================================================
//  INLINED: errordescription.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                             ErrorDescription.mqh |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| returns trade server return code description                     |
//+------------------------------------------------------------------+
string TradeServerReturnCodeDescription(int return_code)
  {
//---
   switch(return_code)
     {
      case TRADE_RETCODE_REQUOTE:            return("Requote");
      case TRADE_RETCODE_REJECT:             return("Request rejected");
      case TRADE_RETCODE_CANCEL:             return("Request canceled by trader");
      case TRADE_RETCODE_PLACED:             return("Order placed");
      case TRADE_RETCODE_DONE:               return("Request is completed");
      case TRADE_RETCODE_DONE_PARTIAL:       return("Request is partially completed");
      case TRADE_RETCODE_ERROR:              return("Request processing error");
      case TRADE_RETCODE_TIMEOUT:            return("Request canceled by timeout");
      case TRADE_RETCODE_INVALID:            return("Invalid request");
      case TRADE_RETCODE_INVALID_VOLUME:     return("Invalid volume in the request");
      case TRADE_RETCODE_INVALID_PRICE:      return("Invalid price in the request");
      case TRADE_RETCODE_INVALID_STOPS:      return("Invalid stops in the request");
      case TRADE_RETCODE_TRADE_DISABLED:     return("Trade is disabled");
      case TRADE_RETCODE_MARKET_CLOSED:      return("Market is closed");
      case TRADE_RETCODE_NO_MONEY:           return("There is not enough money to fulfill the request");
      case TRADE_RETCODE_PRICE_CHANGED:      return("Prices changed");
      case TRADE_RETCODE_PRICE_OFF:          return("There are no quotes to process the request");
      case TRADE_RETCODE_INVALID_EXPIRATION: return("Invalid order expiration date of in the request");
      case TRADE_RETCODE_ORDER_CHANGED:      return("Order state changed");
      case TRADE_RETCODE_TOO_MANY_REQUESTS:  return("Too frequent requests");
      case TRADE_RETCODE_NO_CHANGES:         return("No changes in request");
      case TRADE_RETCODE_SERVER_DISABLES_AT: return("Autotrading disabled by server");
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return("Autotrading disabled by client terminal");
      case TRADE_RETCODE_LOCKED:             return("Request locked for processing");
      case TRADE_RETCODE_FROZEN:             return("Order or position frozen");
      case TRADE_RETCODE_INVALID_FILL:       return("Invalid order filling type"); 
      case TRADE_RETCODE_CONNECTION:         return("No connection with the trade server"); 
      case TRADE_RETCODE_ONLY_REAL:          return("Operation is allowed only for live accounts");     
      case TRADE_RETCODE_LIMIT_ORDERS:       return("The number of pending orders has reached the limit"); 
      case TRADE_RETCODE_LIMIT_VOLUME:       return("The volume of orders and positions for the symbol has reached the limit"); 
     }
//---
   return("Invalid return code of the trade server");
  }
//+------------------------------------------------------------------+
//| returns runtime error code description                           |
//+------------------------------------------------------------------+
string ErrorDescription(int err_code)
  {
//---
   switch(err_code)
     {
      case ERR_INTERNAL_ERROR:               return("Unexpected internal error");
      case ERR_WRONG_INTERNAL_PARAMETER:     return("Wrong parameter in the inner call of the client terminal function");
      case ERR_INVALID_PARAMETER:            return("Wrong parameter when calling the system function");
      case ERR_NOT_ENOUGH_MEMORY:            return("Not enough memory to perform the system function");
      case ERR_STRUCT_WITHOBJECTS_ORCLASS:   return("The structure contains objects of strings and/or dynamic arrays and/or structure of such objects and/or classes");
      case ERR_INVALID_ARRAY:                return("Array of a wrong type, wrong size, or a damaged object of a dynamic array");
      case ERR_ARRAY_RESIZE_ERROR:           return("Not enough memory for the relocation of an array, or an attempt to change the size of a static array");
      case ERR_STRING_RESIZE_ERROR:          return("Not enough memory for the relocation of string");
      case ERR_NOTINITIALIZED_STRING:        return("Not initialized string");
      case ERR_INVALID_DATETIME:             return("Invalid date and/or time");
      case ERR_ARRAY_BAD_SIZE:               return("Requested array size exceeds 2 GB");
      case ERR_INVALID_POINTER:              return("Wrong pointer");
      case ERR_INVALID_POINTER_TYPE:         return("Wrong type of pointer");
      case ERR_FUNCTION_NOT_ALLOWED:         return("System function is not allowed to call");
      case ERR_CHART_WRONG_ID:               return("Wrong chart ID");
      case ERR_CHART_NO_REPLY:               return("Chart does not respond");
      case ERR_CHART_NOT_FOUND:              return("Chart not found");
      case ERR_CHART_NO_EXPERT:              return("No Expert Advisor in the chart that could handle the event");
      case ERR_CHART_CANNOT_OPEN:            return("Chart opening error");
      case ERR_CHART_CANNOT_CHANGE:          return("Failed to change chart symbol and period");
      //case ERR_CHART_WRONG_TIMER_PARAMETER:  return("Wrong parameter for timer");
      case ERR_CHART_CANNOT_CREATE_TIMER:    return("Failed to create timer");
      case ERR_CHART_WRONG_PROPERTY:         return("Wrong chart property ID");
      case ERR_CHART_SCREENSHOT_FAILED:      return("Error creating screenshots");
      case ERR_CHART_NAVIGATE_FAILED:        return("Error navigating through chart");
      case ERR_CHART_TEMPLATE_FAILED:        return("Error applying template");
      case ERR_CHART_WINDOW_NOT_FOUND:       return("Subwindow containing the indicator was not found");
      case ERR_OBJECT_ERROR:                 return("Error working with a graphical object");
      case ERR_OBJECT_NOT_FOUND:             return("Graphical object was not found");
      case ERR_OBJECT_WRONG_PROPERTY:        return("Wrong ID of a graphical object property");
      case ERR_OBJECT_GETDATE_FAILED:        return("Unable to get date corresponding to the value");
      case ERR_OBJECT_GETVALUE_FAILED:       return("Unable to get value corresponding to the date");
      case ERR_MARKET_UNKNOWN_SYMBOL:        return("Unknown symbol");
      case ERR_MARKET_SELECT_ERROR:          return("Symbol is not selected in MarketWatch");
      case ERR_MARKET_WRONG_PROPERTY:        return("Wrong identifier of a symbol property");
      case ERR_MARKET_LASTTIME_UNKNOWN:      return("Time of the last tick is not known (no ticks)");
      case ERR_HISTORY_NOT_FOUND:            return("Requested history not found");
      case ERR_HISTORY_WRONG_PROPERTY:       return("Wrong ID of the history property");
      case ERR_GLOBALVARIABLE_NOT_FOUND:     return("Global variable of the client terminal is not found");
      case ERR_GLOBALVARIABLE_EXISTS:        return("Global variable of the client terminal with the same name already exists");
      case ERR_MAIL_SEND_FAILED:             return("Email sending failed");
      case ERR_PLAY_SOUND_FAILED:            return("Sound playing failed");
      case ERR_MQL5_WRONG_PROPERTY:          return("Wrong identifier of the program property");
      case ERR_TERMINAL_WRONG_PROPERTY:      return("Wrong identifier of the terminal property");
      case ERR_FTP_SEND_FAILED:              return("File sending via ftp failed");
      case ERR_BUFFERS_NO_MEMORY:            return("Not enough memory for the distribution of indicator buffers");
      case ERR_BUFFERS_WRONG_INDEX:          return("Wrong indicator buffer index");
      case ERR_CUSTOM_WRONG_PROPERTY:        return("Wrong ID of the custom indicator property");
      case ERR_ACCOUNT_WRONG_PROPERTY:       return("Wrong account property ID");
      case ERR_TRADE_WRONG_PROPERTY:         return("Wrong trade property ID");
      case ERR_TRADE_DISABLED:               return("Trading by Expert Advisors prohibited");
      case ERR_TRADE_POSITION_NOT_FOUND:     return("Position not found");
      case ERR_TRADE_ORDER_NOT_FOUND:        return("Order not found");
      case ERR_TRADE_DEAL_NOT_FOUND:         return("Deal not found");
      case ERR_TRADE_SEND_FAILED:            return("Trade request sending failed");
      case ERR_INDICATOR_UNKNOWN_SYMBOL:     return("Unknown symbol");
      case ERR_INDICATOR_CANNOT_CREATE:      return("Indicator cannot be created");
      case ERR_INDICATOR_NO_MEMORY:          return("Not enough memory to add the indicator");
      case ERR_INDICATOR_CANNOT_APPLY:       return("The indicator cannot be applied to another indicator");
      case ERR_INDICATOR_CANNOT_ADD:         return("Error applying an indicator to chart");
      case ERR_INDICATOR_DATA_NOT_FOUND:     return("Requested data not found");
      case ERR_INDICATOR_WRONG_INDEX:        return("Wrong index of the requested indicator buffer");
      case ERR_INDICATOR_WRONG_PARAMETERS:   return("Wrong number of parameters when creating an indicator");
      case ERR_INDICATOR_PARAMETERS_MISSING: return("No parameters when creating an indicator");
      case ERR_INDICATOR_CUSTOM_NAME:        return("The first parameter in the array must be the name of the custom indicator");
      case ERR_INDICATOR_PARAMETER_TYPE:     return("Invalid parameter type in the array when creating an indicator");
      case ERR_BOOKS_CANNOT_ADD:             return("Depth Of Market can not be added");
      case ERR_BOOKS_CANNOT_DELETE:          return("Depth Of Market can not be removed");
      case ERR_BOOKS_CANNOT_GET:             return("The data from Depth Of Market can not be obtained");
      case ERR_BOOKS_CANNOT_SUBSCRIBE:       return("Error in subscribing to receive new data from Depth Of Market");
      case ERR_TOO_MANY_FILES:               return("More than 64 files cannot be opened at the same time");
      case ERR_WRONG_FILENAME:               return("Invalid file name");
      case ERR_TOO_LONG_FILENAME:            return("Too long file name");
      case ERR_CANNOT_OPEN_FILE:             return("File opening error");
      case ERR_FILE_CACHEBUFFER_ERROR:       return("Not enough memory for cache to read");
      case ERR_CANNOT_DELETE_FILE:           return("File deleting error");
      case ERR_INVALID_FILEHANDLE:           return("A file with this handle was closed, or was not opening at all");
      case ERR_WRONG_FILEHANDLE:             return("Wrong file handle");
      case ERR_FILE_NOTTOWRITE:              return("The file must be opened for writing");
      case ERR_FILE_NOTTOREAD:               return("The file must be opened for reading");
      case ERR_FILE_NOTBIN:                  return("The file must be opened as a binary one");
      case ERR_FILE_NOTTXT:                  return("The file must be opened as a text");
      case ERR_FILE_NOTTXTORCSV:             return("The file must be opened as a text or CSV");
      case ERR_FILE_NOTCSV:                  return("The file must be opened as CSV");
      case ERR_FILE_READERROR:               return("File reading error");
      case ERR_FILE_BINSTRINGSIZE:           return("String size must be specified, because the file is opened as binary");
      case ERR_INCOMPATIBLE_FILE:            return("A text file must be for string arrays, for other arrays - binary");
      case ERR_FILE_IS_DIRECTORY:            return("This is not a file, this is a directory");
      case ERR_FILE_NOT_EXIST:               return("File does not exist");
      case ERR_FILE_CANNOT_REWRITE:          return("File can not be rewritten");
      case ERR_WRONG_DIRECTORYNAME:          return("Wrong directory name");
      case ERR_DIRECTORY_NOT_EXIST:          return("Directory does not exist");
      case ERR_FILE_ISNOT_DIRECTORY:         return("This is a file, not a directory");
      case ERR_CANNOT_DELETE_DIRECTORY:      return("The directory cannot be removed");
      case ERR_NO_STRING_DATE:               return("No date in the string");
      case ERR_WRONG_STRING_DATE:            return("Wrong date in the string");
      case ERR_WRONG_STRING_TIME:            return("Wrong time in the string");
      case ERR_STRING_TIME_ERROR:            return("Error converting string to date");
      case ERR_STRING_OUT_OF_MEMORY:         return("Not enough memory for the string");
      case ERR_STRING_SMALL_LEN:             return("The string length is less than expected");
      case ERR_STRING_TOO_BIGNUMBER:         return("Too large number, more than ULONG_MAX");
      case ERR_WRONG_FORMATSTRING:           return("Invalid format string");
      case ERR_TOO_MANY_FORMATTERS:          return("Amount of format specifiers more than the parameters");
      case ERR_TOO_MANY_PARAMETERS:          return("Amount of parameters more than the format specifiers");
      case ERR_WRONG_STRING_PARAMETER:       return("Damaged parameter of string type");
      case ERR_STRINGPOS_OUTOFRANGE:         return("Position outside the string");
      case ERR_STRING_ZEROADDED:             return("0 added to the string end, a useless operation");
      case ERR_STRING_UNKNOWNTYPE:           return("�Unknown data type when converting to a string");
      case ERR_WRONG_STRING_OBJECT:          return("Damaged string object");
      case ERR_INCOMPATIBLE_ARRAYS:          return("Copying incompatible arrays. String array can be copied only to a string array, and a numeric array - in numeric array only");
      case ERR_SMALL_ASSERIES_ARRAY:         return("The receiving array is declared as AS_SERIES, and it is of insufficient size");
      case ERR_SMALL_ARRAY:                  return("Too small array, the starting position is outside the array");
      case ERR_ZEROSIZE_ARRAY:               return("An array of zero length");
      case ERR_NUMBER_ARRAYS_ONLY:           return("Must be a numeric array");
      case ERR_ONEDIM_ARRAYS_ONLY:           return("Must be a one-dimensional array");
      case ERR_SERIES_ARRAY:                 return("Timeseries cannot be used");
      case ERR_DOUBLE_ARRAY_ONLY:            return("Must be an array of type double");
      case ERR_FLOAT_ARRAY_ONLY:             return("Must be an array of type float");
      case ERR_LONG_ARRAY_ONLY:              return("Must be an array of type long");
      case ERR_INT_ARRAY_ONLY:               return("Must be an array of type int");
      case ERR_SHORT_ARRAY_ONLY:             return("Must be an array of type short");
      case ERR_CHAR_ARRAY_ONLY:              return("Must be an array of type char");
      default: if(err_code>=ERR_USER_ERROR_FIRST && err_code<ERR_USER_ERROR_LAST)
                                             return("User error "+string(err_code-ERR_USER_ERROR_FIRST));
     }
//---
   return("Unknown error");
  }
//+------------------------------------------------------------------+
//  END INLINED: errordescription.mqh




//+------------------------------------------------------------------+
//| CTrade Class - Open, Close and Modify Orders                                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTrade
  {
protected:

   //create an object "request" inheriting the class MqlTradeRequest
   MqlTradeRequest   request;

   bool              OpenPosition(string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   bool              OpenPending(string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pPrice, double pStop = 0, double pProfit = 0, double pStopLimit = 0, datetime pExpiration = 0, string pComment = NULL);
   void              LogTradeRequest();

   ulong             magicNumber;
   ulong             deviation;
   ENUM_ORDER_TYPE_FILLING fillType;

public:
   MqlTradeResult    result;

   bool              Buy(string pSymbol, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   bool              Sell(string pSymbol, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   void              MagicNumber(ulong pMagic);
   void              Deviation(ulong pDeviation);
   void              FillType(ENUM_ORDER_TYPE_FILLING pFill);

  };





// Open position
// 110 - 120 Code explanation on "Expert Advisor Programming for MetaTrader5""
bool CTrade::OpenPosition(string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pStop, double pProfit, string pComment)
  {
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = pSymbol;
   request.type = pType;
   request.comment = pComment;
   request.deviation = 50;
   request.type_filling = ORDER_FILLING_IOC;
   request.volume = pVolume;

 


// Order loop
   int retryCount = 0;
   int checkCode = 0;

   do
     {
      //assign market price to local variable request.price
      if(pType == ORDER_TYPE_BUY)
        {
         request.price = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
         if(pStop > 0)
            request.sl = request.price - (pStop * _Point);
         if(pProfit > 0)
            request.tp = request.price + (pProfit * _Point);


        }
      else
         if(pType == ORDER_TYPE_SELL)

           {
            request.price = SymbolInfoDouble(pSymbol,SYMBOL_BID);
            if(pStop > 0)
               request.sl = request.price + (pStop * _Point);
            if(pProfit > 0)
               request.tp = request.price - (pProfit * _Point);


           }
      bool sent = OrderSend(request,result);//send order

      checkCode = CheckReturnCode(result.retcode); //stores retcode on local variabe checkcode

      if(checkCode == CHECK_RETCODE_OK)
         break; // exits the loop after order is confirmed on checkcode.
      else
         if(checkCode == CHECK_RETCODE_ERROR) //error handling for failed order
           {
            string errDesc =  (result.retcode);
            Alert("Open market order: Error ",result.retcode," - ",errDesc);
            LogTradeRequest();
            break;
           }
         else
           {
            Print("Server error detected, retrying...");
            Sleep(RETRY_DELAY);
            retryCount++;
           }
     }
   while(retryCount < MAX_RETRIES);

   if(retryCount >= MAX_RETRIES)
     {
      string errDesc = TradeServerReturnCodeDescription(result.retcode);
      Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
     }

   string orderType = CheckOrderType(pType);

   string errDesc = TradeServerReturnCodeDescription(result.retcode);
   Print("Open ",orderType," order #",result.order,": ",result.retcode," - ",errDesc,", Volume: ",result.volume,", Price: ",result.price,", Bid: ",result.bid,", Ask: ",result.ask);



//Returns true if order is successfull and return false if its not
   if(checkCode == CHECK_RETCODE_OK)
     {
      Comment(orderType," position opened at ",result.price," on ",pSymbol);
      return(true);
     }
   else
      return(false);
  }



// Open pending order
bool CTrade::OpenPending(string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pPrice, double pStop, double pProfit, double pStopLimit, datetime pExpiration, string pComment)
  {
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = pSymbol;
   request.type = pType;
   request.sl = pStop;
   request.tp = pProfit;
   request.comment = pComment;
   request.price = pPrice;
   request.volume = pVolume;
   request.stoplimit = pStopLimit;
   request.deviation = deviation;
   request.type_filling = ORDER_FILLING_IOC;
   request.magic = magicNumber;

   if(pExpiration > 0)
     {
      request.expiration = pExpiration;
      request.type_time = ORDER_TIME_SPECIFIED;
     }
   else
      request.type_time = ORDER_TIME_GTC;

// Order loop
   int retryCount = 0;
   int checkCode = 0;

   do
     {
      bool sent = OrderSend(request,result);

      checkCode = CheckReturnCode(result.retcode);

      if(checkCode == CHECK_RETCODE_OK)
         break;
      else
         if(checkCode == CHECK_RETCODE_ERROR)
           {
            string errDesc = TradeServerReturnCodeDescription(result.retcode);
            Alert("Open pending order: Error ",result.retcode," - ",errDesc);
            LogTradeRequest();
            break;
           }
         else
           {
            Print("Server error detected, retrying...");
            Sleep(RETRY_DELAY);
            retryCount++;
           }
     }
   while(retryCount < MAX_RETRIES);

   if(retryCount >= MAX_RETRIES)
     {
      string errDesc = TradeServerReturnCodeDescription(result.retcode);
      Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
     }

   string orderType = CheckOrderType(pType);
   string errDesc = TradeServerReturnCodeDescription(result.retcode);

   Print("Open ",orderType," order #",result.order,": ",result.retcode," - ",errDesc,", Volume: ",result.volume,", Price: ",request.price,
         ", Bid: ",SymbolInfoDouble(pSymbol,SYMBOL_BID),", Ask: ",SymbolInfoDouble(pSymbol,SYMBOL_ASK),", SL: ",request.sl,", TP: ",request.tp,
         ", Stop Limit: ",request.stoplimit,", Expiration: ",request.expiration);

   if(checkCode == CHECK_RETCODE_OK)
     {
      Comment(orderType," order opened at ",request.price," on ",pSymbol);
      return(true);
     }
   else
      return(false);
  }




//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CTrade::LogTradeRequest()
  {
   Print("MqlTradeRequest - action:",request.action,", comment:",request.comment,", deviation:",request.deviation,", expiration:",request.expiration,", magic:",request.magic,", order:",request.order,", position:",request.position,", position_by:",request.position_by,", price:",request.price,", ls:",request.sl,", stoplimit:",request.stoplimit,", symbol:",request.symbol,", tp:",request.tp,", type:",request.type,", type_z:",request.type_filling,", type_time:",request.type_time,", volume:",request.volume);
   Print("MqlTradeResult - ask:",result.ask,", bid:",result.bid,", comment:",result.comment,", deal:",result.deal,", order:",result.order,", price:",result.price,", request_id:",result.request_id,", retcode:",result.retcode,", retcode_external:",result.retcode_external,", volume:",result.volume);
  }


// Trade opening shortcuts
bool CTrade::Buy(string pSymbol, double pVolume, double pStop, double pProfit, string pComment)
  {
   bool success = OpenPosition(pSymbol,ORDER_TYPE_BUY,pVolume,pStop,pProfit,pComment);
   return(success);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CTrade::Sell(string pSymbol, double pVolume, double pStop, double pProfit, string pComment)
  {
   bool success = OpenPosition(pSymbol,ORDER_TYPE_SELL,pVolume,pStop,pProfit,pComment);
   return(success);
  }




// Set magic number
void CTrade::MagicNumber(ulong pMagic)
  {
   magicNumber = pMagic;
  }


// Set deviation
void CTrade::Deviation(ulong pDeviation)
  {
   deviation = pDeviation;
  }


// Set fill type
void CTrade::FillType(ENUM_ORDER_TYPE_FILLING pFill)
  {
   fillType = pFill;
  }


// Return code check
int CheckReturnCode(uint pRetCode)
  {
   int status;
   switch(pRetCode)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_REJECT:
      case TRADE_RETCODE_ERROR:

         status = CHECK_RETCODE_RETRY;
         break;

      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
      case TRADE_RETCODE_PLACED:
      case TRADE_RETCODE_NO_CHANGES:

         status = CHECK_RETCODE_OK;
         break;

      default:
         status = CHECK_RETCODE_ERROR;
     }

   return(status);
  }




//+------------------------------------------------------------------+
//| Miscellaneous Functions & Enumerations                                                            |
//+------------------------------------------------------------------+


enum ENUM_CHECK_RETCODE
  {
   CHECK_RETCODE_OK,
   CHECK_RETCODE_ERROR,
   CHECK_RETCODE_RETRY
  };


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string CheckOrderType(ENUM_ORDER_TYPE pType)
  {
   string orderType;
   if(pType == ORDER_TYPE_BUY)
      orderType = "buy";
   else
      if(pType == ORDER_TYPE_SELL)
         orderType = "sell";
      else
         if(pType == ORDER_TYPE_BUY_STOP)
            orderType = "buy stop";
         else
            if(pType == ORDER_TYPE_BUY_LIMIT)
               orderType = "buy limit";
            else
               if(pType == ORDER_TYPE_SELL_STOP)
                  orderType = "sell stop";
               else
                  if(pType == ORDER_TYPE_SELL_LIMIT)
                     orderType = "sell limit";
                  else
                     if(pType == ORDER_TYPE_BUY_STOP_LIMIT)
                        orderType = "buy stop limit";
                     else
                        if(pType == ORDER_TYPE_SELL_STOP_LIMIT)
                           orderType = "sell stop limit";
                        else
                           orderType = "invalid order type";
   return(orderType);
  }
//+------------------------------------------------------------------+





//  END INLINED: Include/Trade.mqh


//====================================================================
//  INLINED: Include/TrailingStops.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                TrailingStops.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+



//  [already inlined above: errordescription.mqh]
//  [already inlined above: Trade.mqh]


//+------------------------------------------------------------------+
//| Trailing Stop Class                                              |
//+------------------------------------------------------------------+


class CTrailing
{
	protected:
		MqlTradeRequest request;
		
	public:
		MqlTradeResult result;
		
		bool TrailingStop(string pSymbol, int pTrailPoints, int pMinProfit = 0, int pStep = 10);
		bool TrailingStop(string pSymbol, double pTrailPrice, int pMinProfit = 0, int pStep = 10);
		
		bool TrailingStop(ulong pTicket, int pTrailPoints, int pMinProfit = 0, int pStep = 10);
		bool TrailingStop(ulong pTicket, double pTrailPrice, int pMinProfit = 0, int pStep = 10);
		
		bool BreakEven(string pSymbol, int pBreakEven, int pLockProfit=0);
		bool BreakEven(ulong pTicket, int pBreakEven, int pLockProfit=0);
};


// Trailing stop (points)
bool CTrailing::TrailingStop(string pSymbol, int pTrailPoints, int pMinProfit, int pStep)
{
	if(PositionSelect(pSymbol) == true && pTrailPoints > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.symbol = pSymbol;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentStop = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		
		double point = SymbolInfoDouble(pSymbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(pSymbol,SYMBOL_DIGITS);
		
		if(pStep < 10) pStep = 10;
		double step = pStep * point;
		
		double minProfit = pMinProfit * point;
		double trailStop = pTrailPoints * point;
		currentStop = NormalizeDouble(currentStop,digits);
		
		double trailStopPrice;
		double currentProfit;
		
		// Order loop
		int retryCount = 0;
		int checkRes = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				trailStopPrice = SymbolInfoDouble(pSymbol,SYMBOL_BID) - trailStop;
				trailStopPrice = NormalizeDouble(trailStopPrice,digits);
				currentProfit = SymbolInfoDouble(pSymbol,SYMBOL_BID) - openPrice;
				
				if(trailStopPrice > currentStop + step && currentProfit >= minProfit)
				{
					request.sl = trailStopPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				trailStopPrice = SymbolInfoDouble(pSymbol,SYMBOL_ASK) + trailStop;
				trailStopPrice = NormalizeDouble(trailStopPrice,digits);
				currentProfit = openPrice - SymbolInfoDouble(pSymbol,SYMBOL_ASK);
				
				if((trailStopPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
				{	
					request.sl = trailStopPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Trailing stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Trailing stop: ",result.retcode," - ",errDesc,", Old SL: ",currentStop,", New SL: ",request.sl,", Bid: ",SymbolInfoDouble(pSymbol,SYMBOL_BID),", Ask: ",SymbolInfoDouble(pSymbol,SYMBOL_ASK),", Stop Level: ",SymbolInfoInteger(pSymbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	
	else return(false);
}


// Trailing stop (price)
bool CTrailing::TrailingStop(string pSymbol, double pTrailPrice, int pMinProfit, int pStep)
{
	if(PositionSelect(pSymbol) == true && pTrailPrice > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.symbol = pSymbol;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentStop = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		
		double point = SymbolInfoDouble(pSymbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(pSymbol,SYMBOL_DIGITS);
		
		if(pStep < 10) pStep = 10;
		double step = pStep * point;
		double minProfit = pMinProfit * point;
				
		currentStop = NormalizeDouble(currentStop,digits);
		pTrailPrice = NormalizeDouble(pTrailPrice,digits);
		
		double currentProfit;
		
		int retryCount = 0;
		int checkRes = 0;
		
		double bid = 0, ask = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				bid = SymbolInfoDouble(pSymbol,SYMBOL_BID);
				currentProfit = bid - openPrice;
				if(pTrailPrice > currentStop + step && currentProfit >= minProfit) 
				{
					request.sl = pTrailPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				ask = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
				currentProfit = openPrice - ask;
				if((pTrailPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
				{
					request.sl = pTrailPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Trailing stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Trailing stop: ",result.retcode," - ",errDesc,", Old SL: ",currentStop,", New SL: ",request.sl,", Bid: ",bid,", Ask: ",ask,", Stop Level: ",SymbolInfoInteger(pSymbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	else return(false);
}


// Trailing stop (points, hedging orders)
bool CTrailing::TrailingStop(ulong pTicket, int pTrailPoints, int pMinProfit, int pStep)
{
	if(PositionSelectByTicket(pTicket) == true && pTrailPoints > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.position = pTicket;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentStop = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		string symbol = PositionGetString(POSITION_SYMBOL);
		
		double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
		
		if(pStep < 10) pStep = 10;
		double step = pStep * point;
		
		double minProfit = pMinProfit * point;
		double trailStop = pTrailPoints * point;
		currentStop = NormalizeDouble(currentStop,digits);
		
		double trailStopPrice;
		double currentProfit;
		
		// Order loop
		int retryCount = 0;
		int checkRes = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				trailStopPrice = SymbolInfoDouble(symbol,SYMBOL_BID) - trailStop;
				trailStopPrice = NormalizeDouble(trailStopPrice,digits);
				currentProfit = SymbolInfoDouble(symbol,SYMBOL_BID) - openPrice;
				
				if(trailStopPrice > currentStop + step && currentProfit >= minProfit)
				{
					request.sl = trailStopPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				trailStopPrice = SymbolInfoDouble(symbol,SYMBOL_ASK) + trailStop;
				trailStopPrice = NormalizeDouble(trailStopPrice,digits);
				currentProfit = openPrice - SymbolInfoDouble(symbol,SYMBOL_ASK);
				
				if((trailStopPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
				{	
					request.sl = trailStopPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Trailing stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Trailing stop: ",result.retcode," - ",errDesc,", #",pTicket,", Old SL: ",currentStop,", New SL: ",request.sl,", Bid: ",SymbolInfoDouble(symbol,SYMBOL_BID),", Ask: ",SymbolInfoDouble(symbol,SYMBOL_ASK),", Stop Level: ",SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	
	else return(false);
}


// Trailing stop (price, hedging orders)
bool CTrailing::TrailingStop(ulong pTicket, double pTrailPrice, int pMinProfit, int pStep)
{
	if(PositionSelectByTicket(pTicket) == true && pTrailPrice > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.position = pTicket;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentStop = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		string symbol = PositionGetString(POSITION_SYMBOL);
		
		double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
		
		if(pStep < 10) pStep = 10;
		double step = pStep * point;
		double minProfit = pMinProfit * point;
				
		currentStop = NormalizeDouble(currentStop,digits);
		pTrailPrice = NormalizeDouble(pTrailPrice,digits);
		
		double currentProfit;
		
		int retryCount = 0;
		int checkRes = 0;
		
		double bid = 0, ask = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				bid = SymbolInfoDouble(symbol,SYMBOL_BID);
				currentProfit = bid - openPrice;
				if(pTrailPrice > currentStop + step && currentProfit >= minProfit) 
				{
					request.sl = pTrailPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				ask = SymbolInfoDouble(symbol,SYMBOL_ASK);
				currentProfit = openPrice - ask;
				if((pTrailPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
				{
					request.sl = pTrailPrice;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Trailing stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Trailing stop: ",result.retcode," - ",errDesc,", #",pTicket,", Old SL: ",currentStop,", New SL: ",request.sl,", Bid: ",bid,", Ask: ",ask,", Stop Level: ",SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	else return(false);
}



// Break even stop
bool CTrailing::BreakEven(string pSymbol, int pBreakEven, int pLockProfit)
{
	if(PositionSelect(pSymbol) == true && pBreakEven > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.symbol = pSymbol;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentSL = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		
		double point = SymbolInfoDouble(pSymbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(pSymbol,SYMBOL_DIGITS);
		
		double breakEvenStop;
		double currentProfit;
		
		int retryCount = 0;
		int checkRes = 0;
		
		double bid = 0, ask = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				bid = SymbolInfoDouble(pSymbol,SYMBOL_BID);
				breakEvenStop = openPrice + (pLockProfit * point);
				currentProfit = bid - openPrice;
				
				breakEvenStop = NormalizeDouble(breakEvenStop, digits);
				currentProfit = NormalizeDouble(currentProfit, digits);
				
				if(currentSL < breakEvenStop && currentProfit >= pBreakEven * point) 
				{
					request.sl = breakEvenStop;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				ask = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
				breakEvenStop = openPrice - (pLockProfit * point);
				currentProfit = openPrice - ask;
				
				breakEvenStop = NormalizeDouble(breakEvenStop, digits);
				currentProfit = NormalizeDouble(currentProfit, digits);
				
				if((currentSL > breakEvenStop || currentSL == 0) && currentProfit >= pBreakEven * point)
				{
					request.sl = breakEvenStop;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Break even stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Break even stop: ",result.retcode," - ",errDesc,", SL: ",request.sl,", Bid: ",bid,", Ask: ",ask,", Stop Level: ",SymbolInfoInteger(pSymbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	else return(false);
}


// Break even stop (hedging orders)
bool CTrailing::BreakEven(ulong pTicket, int pBreakEven, int pLockProfit)
{
	if(PositionSelectByTicket(pTicket) == true && pBreakEven > 0)
	{
		request.action = TRADE_ACTION_SLTP;
		request.position = pTicket;
		
		long posType = PositionGetInteger(POSITION_TYPE);
		double currentSL = PositionGetDouble(POSITION_SL);
		double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
		string symbol = PositionGetString(POSITION_SYMBOL);
		
		double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
		int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
		
		double breakEvenStop;
		double currentProfit;
		
		int retryCount = 0;
		int checkRes = 0;
		
		double bid = 0, ask = 0;
		
		do 
		{
			if(posType == POSITION_TYPE_BUY)
			{
				bid = SymbolInfoDouble(symbol,SYMBOL_BID);
				breakEvenStop = openPrice + (pLockProfit * point);
				currentProfit = bid - openPrice;
				
				breakEvenStop = NormalizeDouble(breakEvenStop, digits);
				currentProfit = NormalizeDouble(currentProfit, digits);
				
				if(currentSL < breakEvenStop && currentProfit >= pBreakEven * point) 
				{
					request.sl = breakEvenStop;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			else if(posType == POSITION_TYPE_SELL)
			{
				ask = SymbolInfoDouble(symbol,SYMBOL_ASK);
				breakEvenStop = openPrice - (pLockProfit * point);
				currentProfit = openPrice - ask;
				
				breakEvenStop = NormalizeDouble(breakEvenStop, digits);
				currentProfit = NormalizeDouble(currentProfit, digits);
				
				if((currentSL > breakEvenStop || currentSL == 0) && currentProfit >= pBreakEven * point)
				{
					request.sl = breakEvenStop;
					bool sent = OrderSend(request,result);
				}
				else return(false);
			}
			
			checkRes = CheckReturnCode(result.retcode);
		
			if(checkRes == CHECK_RETCODE_OK) break;
			else if(checkRes == CHECK_RETCODE_ERROR)
			{
				string errDesc = TradeServerReturnCodeDescription(result.retcode);
				Alert("Break even stop: Error ",result.retcode," - ",errDesc);
				break;
			}
			else
			{
				Print("Server error detected, retrying...");
				Sleep(RETRY_DELAY);
				retryCount++;
			}
		}
		while(retryCount < MAX_RETRIES);
	
		if(retryCount >= MAX_RETRIES)
		{
			string errDesc = TradeServerReturnCodeDescription(result.retcode);
			Alert("Max retries exceeded: Error ",result.retcode," - ",errDesc);
		}
		
		string errDesc = TradeServerReturnCodeDescription(result.retcode);
		Print("Break even stop: ",result.retcode," - ",errDesc,", #",pTicket,", SL: ",request.sl,", Bid: ",bid,", Ask: ",ask,", Stop Level: ",SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL));
		
		if(checkRes == CHECK_RETCODE_OK) return(true);
		else return(false);
	}
	else return(false);
}
//  END INLINED: Include/TrailingStops.mqh


//====================================================================
//  INLINED: Include/price_action.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                 price_action.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+





//====================================================================
//  INLINED: TradeVirtual.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                 TradeVirtual.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#ifndef MAX_RETRIES
#define MAX_RETRIES 5  // Max retries on error
#endif
#ifndef RETRY_DELAY
#define RETRY_DELAY 3000 // Retry delay in ms
#endif

//  [already inlined above: errordescription.mqh]


struct CandleInfo
  {
   double            body_high;
   double            body_low;
   double            wick_high;
   double            wick_low;
   bool              direction;  // 1 - for bullish , 0 - for bearish

  };



struct PositionInfo
  {
   string            symbol;
   int               ticket;
   datetime          time;
   string            type;
   double            volume;
   double            price;
   double            sl;
   double            tp;
   double            profit;
   string            comment;

  };


struct DealsInfo
  {

   datetime          time;
   int               dealno;
   string            symbol;
   string            type;
   string            direction;
   double            volume;
   double            price;
   double            commission;
   double            swap;
   double            profit;
   double            balance;
   double            realportbalance;
   string            comment;
   double            container;

  };


struct CloseTradeInfo
  {
   datetime          timeopen;
   datetime          timeclose;
   string            symbol;
   string            type;
   double            priceopen;
   double            priceclose;
   double            volume;
   double            commission;
   double            swap;
   double            profit;
   string            result;
   double            balance;


  };



struct VirtualTradeInfo

  {


   PositionInfo      position[];
   DealsInfo         deals[];
   CloseTradeInfo    closetrades[];




  };







//+------------------------------------------------------------------+
//| CTrade Class - Open, Close and Modify Orders                                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTradeVirtual
  {
protected:

   //create an object "request" inheriting the class MqlTradeRequest
   MqlTradeRequest   request;

   bool              OpenPosition(VirtualTradeInfo &vTrade,string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   bool              OpenPending(VirtualTradeInfo &vTrade,int index, string pType);

public:
   MqlTradeResult    result;

   bool              Buy(VirtualTradeInfo &vTrade, string pSymbol, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   bool              Sell(VirtualTradeInfo &vTrade, string pSymbol, double pVolume, double pStop = 0, double pProfit = 0, string pComment = NULL);
   bool              StopLoss(VirtualTradeInfo &vTrade,int index);
   bool              TakeProfit(VirtualTradeInfo &vTrade,int index);
   void              Init(VirtualTradeInfo &VTrade);
  };





// Open position
// 110 - 120 Code explanation on "Expert Advisor Programming for MetaTrader5""
bool CTradeVirtual::OpenPosition(VirtualTradeInfo &vTrade, string pSymbol, ENUM_ORDER_TYPE pType, double pVolume, double pStop, double pProfit, string pComment)
  {

   //Position Info
   //Construct Array for new position
   ArrayResize(vTrade.position,ArraySize(vTrade.position)+1);
   int position_index = ArraySize(vTrade.position)-1;

   vTrade.position[position_index].symbol = pSymbol;
   vTrade.position[position_index].time = TimeCurrent();
   vTrade.position[position_index].volume = pVolume;



   if(pType == ORDER_TYPE_BUY)
     {
      vTrade.position[position_index].type = "long";
      vTrade.position[position_index].price = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
      if(pStop > 0)
         vTrade.position[position_index].sl = vTrade.position[position_index].price - (pStop * _Point);
      if(pProfit > 0)
         vTrade.position[position_index].tp = vTrade.position[position_index].price + (pProfit * _Point);

     }


   if(pType == ORDER_TYPE_SELL)

     {
      vTrade.position[position_index].type = "short";
      vTrade.position[position_index].price = SymbolInfoDouble(pSymbol,SYMBOL_BID);
      if(pStop > 0)
         vTrade.position[position_index].sl = vTrade.position[position_index].price + (pStop * _Point);
      if(pProfit > 0)
         vTrade.position[position_index].tp = vTrade.position[position_index].price - (pProfit * _Point);

     }




//Deal Info
//Construct Array for new deal
   ArrayResize(vTrade.deals,ArraySize(vTrade.deals)+1);
   int deal_index = ArraySize(vTrade.deals)-1;

   vTrade.deals[deal_index].dealno = deal_index +1;
   vTrade.deals[deal_index].symbol = pSymbol;
   vTrade.deals[deal_index].time = TimeCurrent();
   vTrade.deals[deal_index].volume = pVolume;

   vTrade.deals[deal_index].commission = 0.0;
   vTrade.deals[deal_index].swap = 0.0;
   vTrade.deals[deal_index].profit = 0.0;

   vTrade.deals[deal_index].balance =vTrade.deals[deal_index-1].balance + ((vTrade.deals[deal_index].commission)+(vTrade.deals[deal_index].swap)+(vTrade.deals[deal_index].profit));



   if(pType == ORDER_TYPE_BUY)
     {
      vTrade.deals[deal_index].type = "buy";
      vTrade.deals[deal_index].direction = "in";
      vTrade.deals[deal_index].price = SymbolInfoDouble(pSymbol,SYMBOL_ASK);


     }


   if(pType == ORDER_TYPE_SELL)

     {
      vTrade.deals[deal_index].type = "sell";
      vTrade.deals[deal_index].direction = "in";
      vTrade.position[position_index].price = SymbolInfoDouble(pSymbol,SYMBOL_BID);

     }



   vTrade.deals[deal_index].realportbalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (true);


  }


// Open pending order
bool CTradeVirtual::OpenPending(VirtualTradeInfo &vTrade,int index, string pType)
  {

   //Update Deal Container

   //Deal Info
  //Construct Array for new deal
   ArrayResize(vTrade.deals,ArraySize(vTrade.deals)+1);
   int deal_index = ArraySize(vTrade.deals)-1;
   string pSymbol = vTrade.position[index].symbol;

   vTrade.deals[deal_index].dealno = deal_index +1;
   vTrade.deals[deal_index].symbol = vTrade.position[index].symbol;
   vTrade.deals[deal_index].time = TimeCurrent();
   vTrade.deals[deal_index].volume = vTrade.position[index].volume;

   vTrade.deals[deal_index].commission = 0.0;
   vTrade.deals[deal_index].swap = 0.0;
   vTrade.deals[deal_index].profit = 0.0;





   if(pType == "tp" && vTrade.position[index].type == "long")
     {
      vTrade.deals[deal_index].type = "sell";
      vTrade.deals[deal_index].direction = "out";
      vTrade.deals[deal_index].price = SymbolInfoDouble(pSymbol,SYMBOL_BID);
      vTrade.deals[deal_index].profit = (SymbolInfoDouble(pSymbol,SYMBOL_BID) - vTrade.position[index].price)*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }
   if(pType == "sl" && vTrade.position[index].type == "long")
     {
      vTrade.deals[deal_index].type = "sell";
      vTrade.deals[deal_index].direction = "out";
      vTrade.deals[deal_index].price = SymbolInfoDouble(pSymbol,SYMBOL_BID);
      vTrade.deals[deal_index].profit = (SymbolInfoDouble(pSymbol,SYMBOL_BID) - vTrade.position[index].price)*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }

   if(pType == "tp" && vTrade.position[index].type == "short")
     {
      vTrade.deals[deal_index].type = "buy";
      vTrade.deals[deal_index].direction = "out";
      vTrade.deals[deal_index].price = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
      vTrade.deals[deal_index].profit = (vTrade.position[index].price-SymbolInfoDouble(pSymbol,SYMBOL_ASK))*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }

   if(pType == "sl" && vTrade.position[index].type == "short")
     {
      vTrade.deals[deal_index].type = "buy";
      vTrade.deals[deal_index].direction = "out";
      vTrade.deals[deal_index].price = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
      vTrade.deals[deal_index].profit = (vTrade.position[index].price-SymbolInfoDouble(pSymbol,SYMBOL_ASK))*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }



   vTrade.deals[deal_index].balance =vTrade.deals[deal_index-1].balance + ((vTrade.deals[deal_index].commission)+(vTrade.deals[deal_index].swap)+(vTrade.deals[deal_index].profit));



//Closed trade Container

   ArrayResize(vTrade.closetrades,ArraySize(vTrade.closetrades)+1);
   int closedtrade_index = ArraySize(vTrade.closetrades)-1;

   vTrade.closetrades[closedtrade_index].timeopen = vTrade.position[index].time;
   vTrade.closetrades[closedtrade_index].timeclose = TimeCurrent();
   vTrade.closetrades[closedtrade_index].priceopen = vTrade.position[index].price;

   vTrade.closetrades[closedtrade_index].symbol = vTrade.position[index].symbol;
   vTrade.closetrades[closedtrade_index].volume = vTrade.position[index].volume;


   vTrade.closetrades[closedtrade_index].commission = 0.0;
   vTrade.closetrades[closedtrade_index].swap = 0.0;
   vTrade.closetrades[closedtrade_index].profit = 0.0;





   if(vTrade.position[index].type == "long")
     {


      vTrade.closetrades[closedtrade_index].type = "long";
      vTrade.closetrades[closedtrade_index].priceclose = SymbolInfoDouble(pSymbol,SYMBOL_BID);
      vTrade.closetrades[closedtrade_index].profit = (SymbolInfoDouble(pSymbol,SYMBOL_BID) - vTrade.position[index].price)*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }


   if(vTrade.position[index].type == "short")
     {
      vTrade.closetrades[closedtrade_index].type = "short";
      vTrade.closetrades[closedtrade_index].priceclose = SymbolInfoDouble(pSymbol,SYMBOL_ASK);
      vTrade.closetrades[closedtrade_index].profit = (vTrade.position[index].price-SymbolInfoDouble(pSymbol,SYMBOL_ASK))*vTrade.position[index].volume*AccountInfoInteger(ACCOUNT_LEVERAGE);


     }


   if(vTrade.closetrades[closedtrade_index].profit > 0)
      vTrade.closetrades[closedtrade_index].result = "WIN";
   else
      if(vTrade.closetrades[closedtrade_index].profit < 0)
         vTrade.closetrades[closedtrade_index].result = "LOSS";
   vTrade.closetrades[closedtrade_index].balance =vTrade.closetrades[closedtrade_index-1].balance + ((vTrade.closetrades[closedtrade_index].commission)+(vTrade.closetrades[closedtrade_index].swap)+(vTrade.closetrades[closedtrade_index].profit));






   vTrade.deals[deal_index].realportbalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (true);




  }





//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+


// Trade opening shortcuts
bool CTradeVirtual::Buy(VirtualTradeInfo &vTrade, string pSymbol, double pVolume, double pStop, double pProfit, string pComment)
  {
   bool success = OpenPosition(vTrade, pSymbol,ORDER_TYPE_BUY,pVolume,pStop,pProfit,pComment);
   return(success);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CTradeVirtual::Sell(VirtualTradeInfo &vTrade, string pSymbol, double pVolume, double pStop, double pProfit, string pComment)
  {
   bool success = OpenPosition(vTrade, pSymbol,ORDER_TYPE_SELL,pVolume,pStop,pProfit,pComment);
   return(success);
  }




//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CTradeVirtual::StopLoss(VirtualTradeInfo &vTrade,int index)
  {
   bool success = OpenPending(vTrade, index, "sl");
   return(success);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CTradeVirtual::TakeProfit(VirtualTradeInfo &vTrade,int index)
  {
   bool success = OpenPending(vTrade, index, "tp");
   return(success);
  }
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CTradeVirtual::Init(VirtualTradeInfo &VTrade)
  {

//Initialize Deals Container..
//Array Constructor for VTrade.deals...
   ArrayResize(VTrade.deals,ArraySize(VTrade.deals)+1);
   ArrayResize(VTrade.closetrades,ArraySize(VTrade.closetrades)+1);

//ArrayResize(VTrade.position,ArraySize(VTrade.position)+1);
//Populate Vtrade.deals Container
   VTrade.deals[0].time = TimeCurrent();
   VTrade.deals[0].dealno =  1;
   VTrade.deals[0].commission = 0.00;
   VTrade.deals[0].swap = 0.00;
   VTrade.deals[0].profit = AccountInfoDouble(ACCOUNT_BALANCE);
   VTrade.deals[0].balance = AccountInfoDouble(ACCOUNT_BALANCE);
   VTrade.deals[0].type = "balance";
   VTrade.closetrades[0].balance = AccountInfoDouble(ACCOUNT_BALANCE);



  }
//+------------------------------------------------------------------+

//  END INLINED: TradeVirtual.mqh



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Price_Action
  {
protected:

   

   int                      price_action_return_flag;
   int                      trade_count;
   bool                     short_position_flag;
   bool                     long_position_flag;
   bool                     trade_today;
   bool                     candle_reset_resistance;
   bool                     candle_reset_support;
   int                      candle_counter_support;
   int                      candle_counter_resistance;
   int                      m_period_flags;
   
   
   MqlDateTime              m_last_tick_time;
   MqlDateTime              int_time;
   MqlDateTime              time;
   MqlTick                  tick;
   bool                     new_trading_day_flag;
   bool                     first_candle;
   int                      init_time;
   CandleInfo               previous_candle;
   CandleInfo               range;


   void                     GetCandleInfo(CandleInfo &candle);
   void                     ResetVariables();
   void                     FirstCandleUpdateSnR(CandleInfo &range, CandleInfo &previous_candle);
   void                     CandleUpdateSnR(CandleInfo &range, CandleInfo &previous_candle);
   int                      GetBuySellSignal(CandleInfo &range, CandleInfo &previous_candle);
   void                     UpdateFlags(void);
   int                      TimeframesFlags(MqlDateTime &time);
   void                     TimeframeAdd(ENUM_TIMEFRAMES period);


public:

   int                      candle_composition;
   int                      trades_per_day;
   int                      StartOfTradinghour_servertime;
   bool                     new_candle_check(void);
   bool                     new_candle_check2(void);
   int                      Open_Range_Breakout();
   void                     Init();
 

  };
  
  
  /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::GetCandleInfo(CandleInfo &candle)
  {


//assign OPEN,CLOSE, HIGH, LOW

//previous candle is bullish
   if(iClose(_Symbol,_Period,1)> iOpen(_Symbol,_Period,1))

     {

      candle.body_high =iClose(_Symbol,_Period,1);
      candle.body_low =iOpen(_Symbol,_Period,1);
      candle.wick_high =iHigh(_Symbol,_Period,1);
      candle.wick_low= iLow(_Symbol,_Period,1);
      candle.direction = true;

     }

//previous candle is bearish
   else

     {

      candle.body_high =iOpen(_Symbol,_Period,1);
      candle.body_low =iClose(_Symbol,_Period,1);
      candle.wick_high =iHigh(_Symbol,_Period,1);
      candle.wick_low= iLow(_Symbol,_Period,1);
      candle.direction = false;
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::ResetVariables()
  {

   range.wick_high = 0;
   range.wick_low = 0;
   candle_counter_support = 0;
   candle_counter_resistance = 0;
   trade_today = false;
   candle_reset_resistance = false;
   candle_reset_support = false;
   previous_candle.body_high =0;
   previous_candle.body_low =0;
   previous_candle.wick_high =0;
   previous_candle.wick_low=0;
   previous_candle.direction = NULL;
   trade_count = 0;
   short_position_flag = false;
   long_position_flag = false;
   trade_today = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::FirstCandleUpdateSnR(CandleInfo &range, CandleInfo &previous_candle)

  {


   if(fabs((previous_candle.body_high/_Point) - (previous_candle.wick_high/_Point)) > 500)

     {

      range.wick_high = previous_candle.body_high;
      range.body_high = previous_candle.body_high;
      ObjectCreate(0,"My Line",OBJ_HLINE,0,0,range.wick_high);


     }

//Not long wick
   else

     {
      range.wick_high = previous_candle.wick_high;
      range.body_high = previous_candle.body_high;
      ObjectCreate(0,"My Line",OBJ_HLINE,0,0,range.wick_high);
      ObjectCreate(0,"My Line3",OBJ_HLINE,0,0,range.body_high);
      ObjectSetInteger(0,"My Line3",OBJPROP_COLOR,clrBlue);


     }

//Long wick scenario on support update
   if(fabs((previous_candle.body_low/_Point) - (previous_candle.wick_low/_Point)) > 500)

     {
      range.wick_low =  previous_candle.body_low;
      range.body_low = previous_candle.body_low;
      ObjectCreate(0,"My Line1",OBJ_HLINE,0,0,range.wick_low);

     }

//Not long wick
   else
     {
      range.wick_low =  previous_candle.wick_low;
      range.body_low = previous_candle.body_low;
      ObjectCreate(0,"My Line1",OBJ_HLINE,0,0,range.wick_low);
      ObjectCreate(0,"My Line2",OBJ_HLINE,0,0,range.body_low);
      ObjectSetInteger(0,"My Line2",OBJPROP_COLOR,clrBlue);

     }

  }



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::CandleUpdateSnR(CandleInfo &range, CandleInfo &previous_candle)
  {
//update range.wick_high and range.wick_low on the incoming candles
   if(range.wick_high > 0 && range.wick_low > 0 && (candle_counter_resistance <= candle_composition) && (candle_counter_resistance > 0))

     {

      //this will update new resistance given that new candle establishes new high AND significant change (>1) difference AND bullish candle
      if(previous_candle.wick_high > range.wick_high && (fabs(previous_candle.wick_high-range.wick_high)>0.1)  && previous_candle.body_high > range.body_high && fabs(previous_candle.body_high - range.body_high)> 0.1)


        {

         //Long wick scenario on resistance update
         if(fabs((previous_candle.body_high/_Point) - (previous_candle.wick_high/_Point)) > 500)

           {
            range.wick_high = previous_candle.body_high;
            range.body_high = previous_candle.body_high;
            ObjectCreate(0,"My Line",OBJ_HLINE,0,0,range.wick_high);
            ObjectCreate(0,"My Line3",OBJ_HLINE,0,0,range.body_high);
            ObjectSetInteger(0,"My Line3",OBJPROP_COLOR,clrBlue);

            candle_counter_resistance = 1;
            candle_reset_resistance = true;

           }

         else

           {
            range.wick_high = previous_candle.wick_high;
            range.body_high = previous_candle.body_high;
            ObjectCreate(0,"My Line",OBJ_HLINE,0,0,range.wick_high);
            ObjectCreate(0,"My Line3",OBJ_HLINE,0,0,range.body_high);
            ObjectSetInteger(0,"My Line3",OBJPROP_COLOR,clrBlue);

            candle_counter_resistance = 1;
            candle_reset_resistance = true;

           }


        }

     }


   if(range.wick_high > 0 && range.wick_low > 0 && (candle_counter_support <= candle_composition) && (candle_counter_support > 0))

     {


      //this will update new support given that new candle establishes new low AND significant change (>1) difference AND bearish candle

      if(previous_candle.wick_low < range.wick_low && (fabs(previous_candle.wick_low-range.wick_low)>0.1) &&  fabs(previous_candle.body_low - range.body_low)> 0.1 && previous_candle.body_low < range.body_low)

        {


         //Long wick scenario on support update

         if(fabs((previous_candle.body_low/_Point) - (previous_candle.wick_low/_Point)) > 500)

           {
            range.wick_low =  previous_candle.body_low;
            range.body_low = previous_candle.body_low;
            ObjectCreate(0,"My Line1",OBJ_HLINE,0,0,range.wick_low);
            ObjectCreate(0,"My Line2",OBJ_HLINE,0,0,range.body_low);
            ObjectSetInteger(0,"My Line2",OBJPROP_COLOR,clrBlue);


            candle_counter_support = 1;
            candle_reset_support = true;
            //printf("candle_reset_support");


           }


         else
           {
            range.wick_low =  previous_candle.wick_low;
            range.body_low = previous_candle.body_low;
            ObjectCreate(0,"My Line1",OBJ_HLINE,0,0,range.wick_low);
            ObjectCreate(0,"My Line2",OBJ_HLINE,0,0,range.body_low);
            ObjectSetInteger(0,"My Line2",OBJPROP_COLOR,clrBlue);

            candle_counter_support = 1;
            candle_reset_support = true;
            //printf("candle_reset_support");


           }

        }

     }


  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Price_Action::GetBuySellSignal(CandleInfo &range, CandleInfo &previous_candle)
  {

//execute buy orders
   
   //buy order condition: Resistance_candle_counter greater than candle_composition (box range) and previous candle is bullish
   if((candle_counter_resistance> candle_composition) && previous_candle.direction == true)

     {
      //2nd condition a breakout from the range resistance (wick_high)
      if(previous_candle.body_high > range.wick_high)

        {
        //3rd condition is to ensure that EA will only open position once/twice per day depending on user setting..
         if(trade_today == true && long_position_flag == false)
           {
            
            //Update flags 
            if(trades_per_day==2) long_position_flag = true;
            if(trades_per_day==1) trade_today = false;
            return(11); //return BuyLong Signal

           }
        }


     }



//execute sell orders
   //sell order condition: Support_candle_counter greater than candle_composition (box range) and previous candle is bearish
   if((candle_counter_support > candle_composition)&& previous_candle.direction == false)

     {
      //2nd condition a breakdown from the range low (wick_lowh)
      if(previous_candle.body_low < range.wick_low)

        {
         //3rd condition is to ensure that EA will only open position once/twice per day depending on user setting..
         if(trade_today == true && short_position_flag == false)
           {
           
            //Update flags 
            if(trades_per_day==2) short_position_flag = true;
            if(trades_per_day==1) trade_today = false;
            return(10); //return SellShort Signal

           }

        }
     }


   return (0); //return "0" if no signal was generated..

  }



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::UpdateFlags(void)

  {

     {


      if(long_position_flag == true && short_position_flag == true)

        {
         trade_today = false;
        }


      //resets candle counter resistance/support or increments it
      if(candle_reset_resistance == true)
        {
         candle_counter_resistance= 1;
         candle_reset_resistance = false;
        }

      else
        {
         candle_counter_resistance=candle_counter_resistance+1;
        }


      if(candle_reset_support == true)
        {
         candle_counter_support= 1;
         candle_reset_support = false;
        }

      else
        {
         candle_counter_support=candle_counter_support+1;
        }

     }

  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Price_Action::TimeframesFlags(MqlDateTime &time)

  {
//--- set flags for all timeframes
   int result=OBJ_ALL_PERIODS;
//--- if first check, then setting flags all timeframes
   if(m_last_tick_time.min==-1)
      return(result);
//--- check change time
   if(time.min==m_last_tick_time.min &&
      time.hour==m_last_tick_time.hour &&
      time.day==m_last_tick_time.day &&
      time.mon==m_last_tick_time.mon)
      return(OBJ_NO_PERIODS);
//--- new month?
   if(time.mon!=m_last_tick_time.mon)
      return(result);
//--- reset the "new month" flag
   result^=OBJ_PERIOD_MN1;
//--- new day?
   if(time.day!=m_last_tick_time.day)
      return(result);
//--- reset the "new day" and "new week" flags
   result^=OBJ_PERIOD_D1+OBJ_PERIOD_W1;
//--- temporary variables to speed up working with structures
   int curr,delta;
//--- new hour?
   curr=time.hour;
   delta=curr-m_last_tick_time.hour;
   if(delta!=0)
     {
      if(curr%2>=delta)
         result^=OBJ_PERIOD_H2;
      if(curr%3>=delta)
         result^=OBJ_PERIOD_H3;
      if(curr%4>=delta)
         result^=OBJ_PERIOD_H4;
      if(curr%6>=delta)
         result^=OBJ_PERIOD_H6;
      if(curr%8>=delta)
         result^=OBJ_PERIOD_H8;
      if(curr%12>=delta)
         result^=OBJ_PERIOD_H12;
      return(result);
     }
//--- reset all flags for hour timeframes
   result^=OBJ_PERIOD_H1+OBJ_PERIOD_H2+OBJ_PERIOD_H3+OBJ_PERIOD_H4+OBJ_PERIOD_H6+OBJ_PERIOD_H8+OBJ_PERIOD_H12;
//--- new minute?
   curr=time.min;
   delta=curr-m_last_tick_time.min;
   if(delta!=0)
     {
      if(curr%2>=delta)
         result^=OBJ_PERIOD_M2;
      if(curr%3>=delta)
         result^=OBJ_PERIOD_M3;
      if(curr%4>=delta)
         result^=OBJ_PERIOD_M4;
      if(curr%5>=delta)
         result^=OBJ_PERIOD_M5;
      if(curr%6>=delta)
         result^=OBJ_PERIOD_M6;
      if(curr%10>=delta)
         result^=OBJ_PERIOD_M10;
      if(curr%12>=delta)
         result^=OBJ_PERIOD_M12;
      if(curr%15>=delta)
         result^=OBJ_PERIOD_M15;
      if(curr%20>=delta)
         result^=OBJ_PERIOD_M20;
      if(curr%30>=delta)
         result^=OBJ_PERIOD_M30;
     }
//--- result
   return(result);

  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Price_Action::TimeframeAdd(ENUM_TIMEFRAMES period)

  {
   switch(period)
     {
      case PERIOD_M1:
         m_period_flags|=OBJ_PERIOD_M1;
         break;
      case PERIOD_M2:
         m_period_flags|=OBJ_PERIOD_M2;
         break;
      case PERIOD_M3:
         m_period_flags|=OBJ_PERIOD_M3;
         break;
      case PERIOD_M4:
         m_period_flags|=OBJ_PERIOD_M4;
         break;
      case PERIOD_M5:
         m_period_flags|=OBJ_PERIOD_M5;
         break;
      case PERIOD_M6:
         m_period_flags|=OBJ_PERIOD_M6;
         break;
      case PERIOD_M10:
         m_period_flags|=OBJ_PERIOD_M10;
         break;
      case PERIOD_M12:
         m_period_flags|=OBJ_PERIOD_M12;
         break;
      case PERIOD_M15:
         m_period_flags|=OBJ_PERIOD_M15;
         break;
      case PERIOD_M20:
         m_period_flags|=OBJ_PERIOD_M20;
         break;
      case PERIOD_M30:
         m_period_flags|=OBJ_PERIOD_M30;
         break;
      case PERIOD_H1:
         m_period_flags|=OBJ_PERIOD_H1;
         break;
      case PERIOD_H2:
         m_period_flags|=OBJ_PERIOD_H2;
         break;
      case PERIOD_H3:
         m_period_flags|=OBJ_PERIOD_H3;
         break;
      case PERIOD_H4:
         m_period_flags|=OBJ_PERIOD_H4;
         break;
      case PERIOD_H6:
         m_period_flags|=OBJ_PERIOD_H6;
         break;
      case PERIOD_H8:
         m_period_flags|=OBJ_PERIOD_H8;
         break;
      case PERIOD_H12:
         m_period_flags|=OBJ_PERIOD_H12;
         break;
      case PERIOD_D1:
         m_period_flags|=OBJ_PERIOD_D1;
         break;
      case PERIOD_W1:
         m_period_flags|=OBJ_PERIOD_W1;
         break;
      case PERIOD_MN1:
         m_period_flags|=OBJ_PERIOD_MN1;
         break;
      default:
         m_period_flags=WRONG_VALUE;
         break;
     }


  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool  Price_Action::new_candle_check(void)
  {


   TimeCurrent(time);


//checks if the new tick came from a new candle

   if(time.hour != init_time)
     {

      init_time = time.hour;
      return(true);//new candle detected

     }

   else
     {

      return(false);
     }

  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

bool  Price_Action::new_candle_check2(void)

  {
//MqlDateTime time;
   TimeCurrent(time);
   if(m_period_flags!=WRONG_VALUE && m_period_flags!=0)
      if((m_period_flags&TimeframesFlags(time))==0)
        {
         return(false);
        }
   m_last_tick_time=time;
//--- refresh indicators
   return(true);

  }




//+------------------------------------------------------------------+
int  Price_Action::Open_Range_Breakout()
//+------------------------------------------------------------------+
  {

   int y =0;

//get previous candle information then store it to a private member structure "previous_candle"
   GetCandleInfo(previous_candle);


   if(time.hour == StartOfTradinghour_servertime + 1) //flag to be used for timing of 1:00:00 start of trading day
      first_candle = true;   
       

//1st candle of the day, this will only execute at candle open during the  first hour of the trading day at 1:00:00 or 6am at PH time
   if(time.hour == StartOfTradinghour_servertime && first_candle == true)
     {
      
      ResetVariables(); //reset all flags/variables: counters and range high and range low values at new trading day 6am
      first_candle = false;//this is a flag so conditions above will not be executed
      new_trading_day_flag = true;//flag for "2nd candle" and the succedding candles.
     }
//2nd candle of the day
   else
      if(new_trading_day_flag == true)
        {
         FirstCandleUpdateSnR(range,previous_candle); //computes 1st candle range at start of trading day
         new_trading_day_flag = false;
		 UpdateFlags(); 				
        }

      //Sucedding Candles
      else
        {
         CandleUpdateSnR(range,previous_candle); //Updates SNR ranges for the upcoming candles after the 2nd candle
         UpdateFlags(); //update affected flags
        }
        
   y = GetBuySellSignal(range,previous_candle); //Generate buy/sell signals returns "11" for buy long and  "10" for sell short
   
   return (y);

  }



//+------------------------------------------------------------------+
void  Price_Action::Init()
  {



   TimeframeAdd(Period());
   first_candle = true;
   candle_composition = 3;
   trades_per_day =2;
  }
//+------------------------------------------------------------------+

//  END INLINED: Include/price_action.mqh


//====================================================================
//  INLINED: Include/Indicators.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                   Indicators.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+


#define MAX_COUNT 100


//+------------------------------------------------------------------+
//| Base Class                                                       |
//+------------------------------------------------------------------+

class CIndicator
{
	protected:
		int handle;
		double main[];
		
	public:
		CIndicator(void);
		double Main(int pShift=0);
		void Release();
		virtual int Init() { return(handle); }
};

CIndicator::CIndicator(void)
{
	ArraySetAsSeries(main,true);
}

double CIndicator::Main(int pShift)
{
	CopyBuffer(handle,0,0,MAX_COUNT,main);
	double value = NormalizeDouble(main[pShift],_Digits);
	return(value);
}

void CIndicator::Release(void)
{
	IndicatorRelease(handle);
}


//+------------------------------------------------------------------+
//| Moving Average                                                   |
//+------------------------------------------------------------------+

/*

CiMA MA;

sinput string MA;		// Moving Average
input int MAPeriod = 10;
input ENUM_MA_METHOD MAMethod = 0;
input int MAShift = 0;
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE;

MA.Init(_Symbol,_Period,MAPeriod,MAShift,MAMethod,MAPrice);

MA.Main()

*/

class CiMA : public CIndicator
{
	public:
		int Init(string pSymbol,ENUM_TIMEFRAMES pTimeframe,int pMAPeriod,int pMAShift,ENUM_MA_METHOD pMAMethod,ENUM_APPLIED_PRICE pMAPrice);
};

int CiMA::Init(string pSymbol,ENUM_TIMEFRAMES pTimeframe,int pMAPeriod,int pMAShift,ENUM_MA_METHOD pMAMethod,ENUM_APPLIED_PRICE pMAPrice)
{
	handle = iMA(pSymbol,pTimeframe,pMAPeriod,pMAShift,pMAMethod,pMAPrice);
	return(handle);
}


//+------------------------------------------------------------------+
//| RSI                                                              |
//+------------------------------------------------------------------+

/*

CiRSI RSI;

sinput string RS;	// RSI
input int RSIPeriod = 8;
input ENUM_APPLIED_PRICE RSIPrice = PRICE_CLOSE;

RSI.Init(_Symbol,_Period,RSIPeriod,RSIPrice);

RSI.Main()

*/




class CiRSI : public CIndicator
{
	public:
		int Init(string pSymbol, ENUM_TIMEFRAMES pTimeframe, int pRSIPeriod, ENUM_APPLIED_PRICE pRSIPrice);
};

int CiRSI::Init(string pSymbol, ENUM_TIMEFRAMES pTimeframe, int pRSIPeriod, ENUM_APPLIED_PRICE pRSIPrice)
{
	handle = iRSI(pSymbol,pTimeframe,pRSIPeriod,pRSIPrice);
	return(handle);
}


//+------------------------------------------------------------------+
//| Stochastic                                                       |
//+------------------------------------------------------------------+

/*

CiStochastic Stoch;

sinput string STO;	// Stochastic
input int KPeriod = 10;
input int DPeriod = 3;
input int Slowing = 3;
input ENUM_MA_METHOD StochMethod = MODE_SMA;
input ENUM_STO_PRICE StochPrice = STO_LOWHIGH;

Stoch.Init(_Symbol,_Period,KPeriod,DPeriod,Slowing,StochMethod,StochPrice);

Stoch.Main()
Stoch.Signal()

*/




//+------------------------------------------------------------------+
//| Bollinger Bands                                                  |
//+------------------------------------------------------------------+

/*

CiBollinger Bands;

sinput string BB;		// Bollinger Bands
input int BandsPeriod = 20;
input int BandsShift = 0;
input double BandsDeviation = 2;
input ENUM_APPLIED_PRICE BandsPrice = PRICE_CLOSE; 

Bands.Init(_Symbol,_Period,BandsPeriod,BandsShift,BandsDeviation,BandsPrice);

Bands.Upper()
Bands.Lower()

*/




//+------------------------------------------------------------------+
//| Blank Indicator Class Templates                                  |
//+------------------------------------------------------------------+

/* 

Replace _INDNAME_ with the name of the indicator.
Replace _INDFUNC_ with the name of the correct technical indicator function.
Add appropriate input parameters (...) to Init() function.
Rename Buffer1(), Buffer2(), etc. to something user-friendly.
Add or remove buffer arrays and functions as necessary.



// Single Buffer Indicator

class Ci_INDNAME_ : public CIndicator
{
	public:
		int Init(string pSymbol, ENUM_TIMEFRAMES pTimeframe, ... );
}; 


int Ci_INDNAME_::Init(string pSymbol,ENUM_TIMEFRAMES pTimeframe, ... )
{
	handle = _INDFUNC_(pSymbol,pTimeframe, ... );
	return(handle);
}



// Multi-Buffer Indicator

class Ci_INDNAME_ : public CIndicator
{
	private:
		double buffer1[];
		double buffer2[];
		
	public:
		int Init(string pSymbol,ENUM_TIMEFRAMES pTimeframe, ... );
		double Buffer1(int pShift=0);
		double Buffer2(int pShift=0);
		Ci_INDNAME_();
}; 


Ci_INDNAME_::Ci_INDNAME_()
{
	ArraySetAsSeries(buffer1,true);
	ArraySetAsSeries(buffer2,true);
}


int Ci_INDNAME_::Init(string pSymbol,ENUM_TIMEFRAMES pTimeframe,...)
{
	handle = _INDFUNC_(pSymbol,pTimeframe,...);
	return(handle);
}


double Ci_INDNAME_::Buffer1(int pShift)
{
	CopyBuffer(handle,1,0,MAX_COUNT,buffer1);
	double value = NormalizeDouble(buffer1[pShift],_Digits);
	return(value); 
} 


double Ci_INDNAME_::Buffer2(int pShift)
{
	CopyBuffer(handle,1,0,MAX_COUNT,buffer2);
	double value = NormalizeDouble(buffer2[pShift],_Digits);
	return(value); 
} 


*/
//  END INLINED: Include/Indicators.mqh

//  [already inlined above: Include/TradeVirtual.mqh]

//====================================================================
//  INLINED: Include/TrailingStopsVirtual.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                            TradeStopsVirtual.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+



//  [already inlined above: errordescription.mqh]
//  [already inlined above: TradeVirtual.mqh]


//+------------------------------------------------------------------+
//| Trailing Stop Class                                              |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTrailingVirtual
  {
protected:
   MqlTradeRequest   request;

public:
   MqlTradeResult    result;



   bool              TrailingStop(VirtualTradeInfo &vTrade, int index,  int pTrailPoints, int pMinProfit = 0, int pStep = 10);
   bool              TrailingStop(VirtualTradeInfo &vTrade, int index,  double pTrailPrice, int pMinProfit = 0, int pStep = 10);


  };




// Trailing stop (points, hedging orders)
bool CTrailingVirtual::TrailingStop(VirtualTradeInfo &vTrade, int index, int pTrailPoints, int pMinProfit, int pStep)
  {
   if(pTrailPoints > 0)
     {


      string posType = vTrade.position[index].type;
      double currentStop = vTrade.position[index].sl;
      double openPrice = vTrade.position[index].price;
      string symbol = vTrade.position[index].symbol;

      double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);

      if(pStep < 10)
         pStep = 10;
      double step = pStep * point;

      double minProfit = pMinProfit * point;
      double trailStop = pTrailPoints * point;
      currentStop = NormalizeDouble(currentStop,digits);

      double trailStopPrice;
      double currentProfit;





      if(posType == "long")
        {
         trailStopPrice = SymbolInfoDouble(symbol,SYMBOL_BID) - trailStop;
         trailStopPrice = NormalizeDouble(trailStopPrice,digits);
         currentProfit = SymbolInfoDouble(symbol,SYMBOL_BID) - openPrice;

         if(trailStopPrice > currentStop + step && currentProfit >= minProfit)
           {
            vTrade.position[index].sl = trailStopPrice;
            vTrade.position[index].tp = 0;
            return(true);
           }
         else

            return(false);


        }


      else
         if(posType == "short")
           {
            trailStopPrice = SymbolInfoDouble(symbol,SYMBOL_ASK) + trailStop;
            trailStopPrice = NormalizeDouble(trailStopPrice,digits);
            currentProfit = openPrice - SymbolInfoDouble(symbol,SYMBOL_ASK);

            if((trailStopPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
              {
               vTrade.position[index].sl = trailStopPrice;
               vTrade.position[index].tp = 0;
               return(true);
              }
            else
               return(false);

           }
         else
            return(false);
     }

   else
      return(false);


  }


// Trailing stop (price, hedging orders)
bool CTrailingVirtual::TrailingStop(VirtualTradeInfo &vTrade, int index, double pTrailPrice, int pMinProfit, int pStep)
  {
   if(pTrailPrice > 0)
     {


      long posType = PositionGetInteger(POSITION_TYPE);
      double currentStop = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      string symbol = PositionGetString(POSITION_SYMBOL);

      double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);

      if(pStep < 10)
         pStep = 10;
      double step = pStep * point;
      double minProfit = pMinProfit * point;

      currentStop = NormalizeDouble(currentStop,digits);
      pTrailPrice = NormalizeDouble(pTrailPrice,digits);

      double currentProfit;
      double trailStopPrice =0.0;



      double bid = 0, ask = 0;



      if(posType == POSITION_TYPE_BUY)
        {
         bid = SymbolInfoDouble(symbol,SYMBOL_BID);
         currentProfit = bid - openPrice;
         if(pTrailPrice > currentStop + step && currentProfit >= minProfit)
           {
            vTrade.position[index].sl = trailStopPrice;
            return(true);
           }
         else
            return(false);
        }
      else
         if(posType == POSITION_TYPE_SELL)
           {
            ask = SymbolInfoDouble(symbol,SYMBOL_ASK);
            currentProfit = openPrice - ask;
            if((pTrailPrice < currentStop - step || currentStop == 0) && currentProfit >= minProfit)
              {
               vTrade.position[index].sl = trailStopPrice;
               return(true);
              }
            else
               return(false);
           }



         else
            return(false);

     }
   else
      return(false);
  }




//+------------------------------------------------------------------+

//+------------------------------------------------------------------+



//+------------------------------------------------------------------+

//+------------------------------------------------------------------+

//  END INLINED: Include/TrailingStopsVirtual.mqh


//====================================================================
//  INLINED: Include/MoneyManagement.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                               MoneyManagement.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#define MAX_PERCENT 10		// Maximum balance % used in money management


// Risk-based money management
double MoneyManagement(string pSymbol,double pFixedVol,double pPercent,int pStopPoints)
{
	double tradeSize;
	
	if(pPercent > 0 && pStopPoints > 0)
	{
		if(pPercent > MAX_PERCENT) pPercent = MAX_PERCENT;
		
		double margin = AccountInfoDouble(ACCOUNT_BALANCE) * (pPercent / 100);
		double tickSize = SymbolInfoDouble(pSymbol,SYMBOL_TRADE_TICK_VALUE);
		
		tradeSize = (margin / pStopPoints) / tickSize;
		tradeSize = VerifyVolume(pSymbol,tradeSize);
		
		return(tradeSize);
	}
	else
	{
		tradeSize = pFixedVol;
		tradeSize = VerifyVolume(pSymbol,tradeSize);
		
		return(tradeSize);
	}
}


// Verify and adjust trade volume
double VerifyVolume(string pSymbol,double pVolume)
{
	double minVolume = SymbolInfoDouble(pSymbol,SYMBOL_VOLUME_MIN);
	double maxVolume = SymbolInfoDouble(pSymbol,SYMBOL_VOLUME_MAX);
	double stepVolume = SymbolInfoDouble(pSymbol,SYMBOL_VOLUME_STEP);
	
	double tradeSize;
	if(pVolume < minVolume) tradeSize = minVolume;
	else if(pVolume > maxVolume) tradeSize = maxVolume;
	else tradeSize = MathRound(pVolume / stepVolume) * stepVolume;
	
	if(stepVolume >= 0.1) tradeSize = NormalizeDouble(tradeSize,1);
	else tradeSize = NormalizeDouble(tradeSize,2);
	
	return(tradeSize);
}


// Calculate distance between order price and stop loss in points
double StopPriceToPoints(string pSymbol,double pStopPrice, double pOrderPrice)
{
	double stopDiff = MathAbs(pStopPrice - pOrderPrice);
	double getPoint = SymbolInfoDouble(pSymbol,SYMBOL_POINT);
	double priceToPoint = stopDiff / getPoint;
	return(priceToPoint);
}

//  END INLINED: Include/MoneyManagement.mqh

#include <Math\Stat\Normal.mqh>   // MT5 standard library - only MathSum() is used

//====================================================================
//  INLINED: Include/RiskManagement.mqh
//====================================================================
//+------------------------------------------------------------------+
//|                                                 TradeVirtual.mqh |
//|                                              Playground Inc 2021 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+






void MonitorVirtualPostion(VirtualTradeInfo &VTrade)

  {

   int i = 0;
   int total_positions = ArraySize(VTrade.position);
//printf(ArraySize(VTrade.position));


   if(total_positions!=0)
     {

      for(i=0 ; i <= total_positions -1; i++)

        {


         if(VTrade.position[i].type == "long" && SymbolInfoDouble(_Symbol,SYMBOL_BID) >= VTrade.position[i].tp &&VTrade.position[i].tp > 0)

           {

            //update deals
            tradevirtual.TakeProfit(VTrade,i);

            //update close trade
            //Update position
            VTrade.position[i].comment = "closed";
           }

         //Print("Stoploss = ",  VTrade.position[i].sl);
         //Print("Current_Price = ", SymbolInfoDouble(_Symbol,SYMBOL_BID));
         if(VTrade.position[i].type == "long" && SymbolInfoDouble(_Symbol,SYMBOL_BID) <= VTrade.position[i].sl)

           {

            //update deals
            tradevirtual.StopLoss(VTrade,i);

            //update close trade
            //Update position
            VTrade.position[i].comment = "closed";

           }


         if(VTrade.position[i].type == "short" && SymbolInfoDouble(_Symbol,SYMBOL_ASK) <= VTrade.position[i].tp && VTrade.position[i].tp > 0)

           {
            //update deals
            tradevirtual.TakeProfit(VTrade,i);

            //update close trade
            //Update position
            VTrade.position[i].comment = "closed";

           }


         if(VTrade.position[i].type == "short" && SymbolInfoDouble(_Symbol,SYMBOL_ASK) >= VTrade.position[i].sl)

           {

            //update deals
            tradevirtual.StopLoss(VTrade,i);


            //update close trade
            //Update position
            VTrade.position[i].comment = "closed";

           }

        }


      //Update Position container - resizing
      bool position_update = false;
      i=0;
      do

        {
         total_positions = ArraySize(VTrade.position);
         for(i=0 ; i <= total_positions -1; i++)

           {

            if(total_positions ==0)
               position_update = true;

            if(VTrade.position[i].comment == "closed")
              {
               //remove this element on the array
               ArrayRemove(VTrade.position,i,1);


               if(i== total_positions-1)

                 {
                  position_update = true;
                 }

               break;

              }

            if(i== total_positions-1)

              {
               position_update = true;
              }

           }
        }
      while(position_update == false);

     }

  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckSlope(VirtualTradeInfo &VTrade, int offset_length)
//+------------------------------------------------------------------+
  {


   int deal_size = ArraySize(VTrade.deals);
   int index = deal_size -1;
//int offset_length = 5;

   if(deal_size > offset_length)
     {

      if((VTrade.deals[index].balance - VTrade.deals[index-(offset_length)].balance)>0)

        {


         return(true);
        }
      else
         return(false);
     }

   else
      return(false);

  }
//+------------------------------------------------------------------+
bool LossStreakCounter(VirtualTradeInfo &VTrade, double streak)
  {
   
   
   int index = ArraySize(VTrade.closetrades)-1;
   double container[];
   ArrayResize(container,streak);
   int i =0;

   
   if(ArraySize(VTrade.closetrades) >= streak)
     {

      for(i = index ; i> index - streak; i--)

        {

         if(VTrade.closetrades[i].result == "WIN")
            container[index - i] = 0;

         if(VTrade.closetrades[i].result == "LOSS")
            container[index - i] = 1;

        }

      if(MathSum(container) == streak)
        {
         return(true);
        }
      else
         return(false);
     }

   else
      return (false);
      
     

  }
//+------------------------------------------------------------------+


//  END INLINED: Include/RiskManagement.mqh




//Input Variables
input group  "SymBolInformation"
input int StartOfTradingHour_ServerTime = 1;

input group  "Trade Management"
input int TakeProfit =1200;
input int StopLoss =400;
input int MaxTradePerDay =2;
input bool LongPosition = true;
input bool ShortPosition = true;

input group "Trail Management"
input bool EnableTrail=true;

input group "Risk Management"
input double MaxEquityDrawdownPercent = 10;
input double MaxRiskPerTradePercent = 1;
input double FixedVolume = 0.1;


input group "Advanced Equity Monitoring Module"
input bool SlopeDetection = false;
input int           LossStreakLimit   = 0;

input group "Indicators"
input int PriceActionORB_CandleComposition = 3;


//Global Variables
bool execute_trade;
double capital;
int indicator_2;
bool indicator_3;
double TradeVolume = FixedVolume;


//Class objects

//Trade management Module
//++++++++++++++++++++++++
CTrade trade; //a class for executing orders on the server
CTrailing trail; //a class for trail stop

//Indicators Module
//++++++++++++++++++++++++
Price_Action pa;// an indicator class for price action
CiMA MA100; //an indicator class for moving averages


//Virtual Trading Environment Module
//++++++++++++++++++++++++++++++++++++
CTradeVirtual tradevirtual;// a class for executing orders on virtual trade environment
CTrailingVirtual trailvirtual; //a class for trail stop virtual
VirtualTradeInfo VTrade; //a class for storing virtual information: details on  position, deals and closed trades




//Working Code
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// Event handler: Initialization
int OnInit()
  {
  
   //Initialize Price action object for default or user input
   pa.Init();
   pa.candle_composition = PriceActionORB_CandleComposition;
   pa.trades_per_day = MaxTradePerDay;
   pa.StartOfTradinghour_servertime = StartOfTradingHour_ServerTime;
   

   //Initialize virtual trade environment
   tradevirtual.Init(VTrade);

   //******************************
   //Extra Variables (test cases)
   execute_trade = true;
   capital = AccountInfoDouble(ACCOUNT_BALANCE);
   return(INIT_SUCCEEDED);   // was return("Initialization Success") - OnInit returns int
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// Event handler: Execute each tick that will arrive from the server
void OnTick()
  {
   
   
   RiskManagementModule();
   if(EnableTrail) TrailModule();
   if(pa.new_candle_check2())
     {
      IndicatorModule();
      ExecuteOrders();
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//End of Program




/////////////////////////////////////////////////////////////////////
//                     Functions
/////////////////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| //Risk Management Module     
//|      
//|  **MonitoringVirtualPosition - Monitors and Closes virtual position 
//|                                and update virtualtrade information
//|  
                              
//+------------------------------------------------------------------+
void RiskManagementModule(void)

  {
  
   //Virtual Equity Monitoring
   MonitorVirtualPostion(VTrade); 

   //Setting Up Equity Trail, will stop executing order once hit, off by default if input is "0"
   if(MaxEquityDrawdownPercent!=0)
     {
      if(AccountInfoDouble(ACCOUNT_BALANCE)>capital)
         capital = AccountInfoDouble(ACCOUNT_BALANCE);
      //  FIX (not upstream): the two statements below were BOTH indented under
      //  this if, but there were no braces - so only the printf was conditional
      //  and "execute_trade = false" ran on EVERY tick whenever
      //  MaxEquityDrawdownPercent != 0. Enabling the drawdown guard therefore
      //  stopped the EA trading at all, which is why the shipped default_input.set
      //  has MaxEquityDrawdownPercent=0.0 - disabling it was the only way to get
      //  any trades. You got no protection, or no trades, and nothing in between.
      if(100*((AccountInfoDouble(ACCOUNT_BALANCE) - capital)/capital) < -1* MaxEquityDrawdownPercent)
        {
         printf("Equity drawdown guard hit: %.2f%% <= -%.2f%% - no further entries",
                100*((AccountInfoDouble(ACCOUNT_BALANCE) - capital)/capital),
                MaxEquityDrawdownPercent);
         execute_trade = false;
        }
     }


   //This module will detect if Lossing streak ended depending on the input integer and if equity is recovering, upward
   if(SlopeDetection || LossStreakLimit!=0)
     {
      bool LossStreak_flag = LossStreakCounter(VTrade,3); //Lossing Streak Detection
      bool Slope_Equity_Flag = CheckSlope(VTrade,12); // Slope Equity Monitoring

      if(LossStreak_flag)
         execute_trade = false;
      if(Slope_Equity_Flag == true && LossStreak_flag == false)
         execute_trade = true;
     }
   
   //Dynamic Position Sizing Relative to port size, or FixedVolume for default if no input in MaxRiskPerTradePercent
   TradeVolume = MoneyManagement(_Symbol,FixedVolume,MaxRiskPerTradePercent,StopLoss);


  }



//+------------------------------------------------------------------+
//| //Trail Stop Module                                              |
//+------------------------------------------------------------------+
void TrailModule(void)

  {
   int i = 0;
   int total_positions = PositionsTotal();


   //RealPort Trail Module, will loop on all open positions to check if trail is hit
   if(total_positions!=0)
      for(i=0 ; i <= total_positions -1; i++)
        {
         trail.TrailingStop(PositionGetTicket(i),700,100,10); //  set 700 trail stop below sa TP then min profit is  100 for secure profits, 10 is the step size
        }


   //Virtual Port Trail Module, will loop on all open positions to check if trail is hit
   int j=0;
   int total_positions_virtual = ArraySize(VTrade.position);
   if(total_positions_virtual!=0)
      for(j=0 ; j <= total_positions_virtual -1; j++)
        {
         trailvirtual.TrailingStop(VTrade,j,700,100,10); //  set 700 trail stop below sa TP then min profit is  100 for secure profits, 10 is the step size
        }
  }




//+------------------------------------------------------------------+
//| //Indicators Module                                              |
//+------------------------------------------------------------------+
void IndicatorModule(void)
  {


   //Price action indicator
   //outputs "11" for Long position signal and "10" for Short position signal
   indicator_2 = pa.Open_Range_Breakout(); 


   // Moving Average indicator
   MA100.Init(_Symbol,PERIOD_CURRENT,100,0,MODE_SMA,PRICE_CLOSE); 
   double ma = MA100.Main(0); // get the value of the latest ma value wrt to latest candle
   iClose(_Symbol,_Period,1) > ma ? indicator_3 = true:indicator_3 = false; //compare the value with the candle

  }



//+------------------------------------------------------------------+
//| //Trade Execution Module                                          |
//+------------------------------------------------------------------+

void ExecuteOrders(void)

  {

//Buy/Sell Order: //Execute buy/sell orders given the indicators and user inputs if its enabled
   if(indicator_2 == 11 && LongPosition)
     {

      tradevirtual.Buy(VTrade,_Symbol,TradeVolume,StopLoss,TakeProfit);
      if(execute_trade)//if this is false then the equity hits its maximum draw down as input by the user
         trade.Buy(_Symbol,TradeVolume,StopLoss,TakeProfit);
     }


   if(indicator_2 == 10 && ShortPosition)
     {
      tradevirtual.Sell(VTrade,_Symbol,TradeVolume,StopLoss,TakeProfit);
      if(execute_trade)//if this is false then the equity hits its maximum draw down as input by the user
         trade.Sell(_Symbol,TradeVolume,StopLoss,TakeProfit);

     }

  }


//+------------------------------------------------------------------+
