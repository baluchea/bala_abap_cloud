@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Booking Processor projection entity'
@Metadata.ignorePropagatedAnnotations: false
@VDM.viewType: #CONSUMPTION
@Metadata.allowExtensions: true
define view entity zba_ab_booking_processor as projection on zba_ab_booking
{
    key TravelId,
    key BookingId,
    BookingDate,
    CustomerId,
    CarrierId,
    ConnectionId,
    FlightDate,
    FlightPrice,
    CurrencyCode,
    BookingStatus,
    LastChangedAt,
    /* Associations */
    _BookingStatus,
    _BookingSuppl:redirected to composition child zba_ab_booksuppl_processor,
    _Carrier,
    _Connection,
    _Customer,
    _Travel:redirected to parent zba_ab_travel_processor
}
