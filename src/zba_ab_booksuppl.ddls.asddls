@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Booking Supplement child entity'
@Metadata.ignorePropagatedAnnotations: true
define view entity zba_ab_booksuppl as select from /dmo/booksuppl_m
association to parent zba_ab_booking as _Booking
on $projection.TravelId = _Booking.TravelId
and $projection.BookingId = _Booking. BookingId
association[1..1] to zba_ab_travel as _Travel
on $projection.TravelId = _Travel.TravelId
association[1..1] to /DMO/I_Supplement as _Supplement
on $projection.BookingSupplementId = _Supplement.SupplementID
association[1..*] to /DMO/I_SupplementText as _Supplementtext
on $projection.SupplementId = _Supplementtext.SupplementID
{
    key travel_id as TravelId,
    key booking_id as BookingId,
    key booking_supplement_id as BookingSupplementId,
    supplement_id as SupplementId,
    @Semantics.amount.currencyCode: 'CurrencyCode'
    price as Price,
    currency_code as CurrencyCode,
    @Semantics.systemDateTime.lastChangedAt: true
    last_changed_at as LastChangedAt,
    _Booking,
    _Travel,
    _Supplement,
    _Supplementtext
}
