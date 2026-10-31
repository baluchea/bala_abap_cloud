@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Supplement processor projection entity'
@Metadata.ignorePropagatedAnnotations: false
@Metadata.allowExtensions: true
define view entity zba_ab_booksuppl_processor as projection on zba_ab_booksuppl
{
    key TravelId,
    key BookingId,
    key BookingSupplementId,
    SupplementId,
    Price,
    CurrencyCode,
    LastChangedAt,
    /* Associations */
    _Booking:redirected to parent zba_ab_booking_processor,
    _Supplement,
    _Supplementtext,
    _Travel:redirected to zba_ab_travel_processor
}
