@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bookind CDS entity as first Child'
@Metadata.ignorePropagatedAnnotations: true
@VDM.viewType: #COMPOSITE
define view entity zba_ab_booking as select from /dmo/booking_m
composition[0..*] of zba_ab_booksuppl as _BookingSuppl
association to parent zba_ab_travel as _Travel
on $projection.TravelId = _Travel.TravelId
association of one to one /DMO/I_Customer as _Customer
on $projection.CustomerId = _Customer.CustomerID
association of one to one /DMO/I_Carrier as _Carrier
on $projection.CarrierId = _Carrier.AirlineID
association of one to one /DMO/I_Connection as _Connection
on $projection.CarrierId = _Connection.AirlineID
and $projection.ConnectionId = _Connection.ConnectionID
association of one to one /DMO/I_Booking_Status_VH as _BookingStatus
on $projection.BookingStatus = _BookingStatus.BookingStatus
association of one to one I_Currency as _Currency on
    $projection.CurrencyCode = _Currency.Currency
{
  key travel_id as TravelId,
  key booking_id as BookingId,
  booking_date as BookingDate,
  @Consumption.valueHelpDefinition: [{ entity: {
        name: '/DMO/I_Customer',
        element: 'CustomerID'
    }  }]
  customer_id as CustomerId,
  @Consumption.valueHelpDefinition: [{ entity: {
        name: '/DMO/I_Carrier',
        element: 'AirlineID'
    }  }]
  carrier_id as CarrierId,
  @Consumption.valueHelpDefinition: [{ entity: {
        name: '/DMO/I_Connection',
        element: 'ConnectionID'
    },additionalBinding: [{
      localElement: 'CarrierId',
      element: 'AirlineID' 
  }]
          }]
  connection_id as ConnectionId,
  flight_date as FlightDate,
  @Semantics.amount.currencyCode: 'CurrencyCode'
  flight_price as FlightPrice,
  @Consumption.valueHelpDefinition: [{ entity: {
        name: 'I_Currency',
        element: 'Currency'
    }  }]
  currency_code as CurrencyCode,
  @Consumption.valueHelpDefinition: [{ entity: {
        name: '/DMO/I_Booking_Status_VH',
        element: 'BookingStatus'
    }  }]
  booking_status as BookingStatus,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt,
  _Customer,
  _Carrier,
  _Connection,
  _BookingStatus,
  _Travel,
  _BookingSuppl,
  _Currency
}
