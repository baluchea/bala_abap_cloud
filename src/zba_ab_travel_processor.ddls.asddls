@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Projection for Root travel entity'
@Metadata.ignorePropagatedAnnotations: false
@VDM.viewType: #CONSUMPTION
define root view entity zba_ab_travel_processor as projection on zba_ab_travel
{
    key TravelId,
    AgencyId,
    CustomerId,
    BeginDate,
    EndDate,
    BookingFee,
    TotalPrice,
    CurrencyCode,
    Description,
    OverallStatus,
    CreatedBy,
    CreatedAt,
    LastChangedBy,
    LastChangedAt,
    /* Associations */
    _Agency,
    _Booking:redirected to composition child zba_ab_booking_processor,
    _Currency,
    _Customer,
    _OverallStatus
}
