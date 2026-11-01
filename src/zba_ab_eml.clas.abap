CLASS zba_ab_eml DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
    data:lv_Ops TYPE c value 'R'.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zba_ab_eml IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    CASE lv_ops.
      WHEN 'R'.
        "READ ENTITY bdef
        READ ENTITY zba_ab_travel
            ALL FIELDS WITH VALUE #( ( %key-TravelId = 9004 ) )
            RESULT DATA(read_travel)
            FAILED DATA(failed_travel).

        READ ENTITY zba_ab_travel
        FIELDS ( AgencyId agencyname CustomerId CustomerName )
        WITH CORRESPONDING #( read_travel )
        RESULT DATA(read_travel_fields)
        FAILED DATA(read_failed_travel_fields).

        "READ ENTITY bdef (read-by-association operation)
        READ entity zba_ab_travel
        by \_Booking
        ALL FIELDS WITH value #( (  %key-TravelId =  9004 ) )
        RESULT data(result_rba_booking)
        FAILED data(failed_rba_booking).

        "READ ENTITIES OF bdef
        READ ENTITIES OF zba_ab_travel
        ENTITY Travel
        ALL FIELDS WITH value #( ( %key-TravelId = 9004 )
                                 ( %key-TravelId = 9002 ) )
        RESULT data(read_entities_travel_result)
        ENTITY Booking
        ALL FIELDS WITH value #( (  %key-Travelid = 9004
                                   %key-BookingId = 001 )
                                 (  %key-Travelid = 9002
                                   %key-BookingId = 001  )
                                 (  %key-Travelid = 9003
                                   %key-BookingId = 001  ) )
         RESULT data(read_entities_booking_result)

         ENTITY BookSuppl
         all FIELDS with value #( ( %key-TravelId = 9004
                                    %key-BookingId = 001
                                    %key-BookingSupplementId = 001
                                  )
                                  ( %key-TravelId = 9002
                                    %key-BookingId = 001
                                    %key-BookingSupplementId = 001
                                  )
                                  ( %key-TravelId = 9003
                                    %key-BookingId = 001
                                    %key-BookingSupplementId = 001
                                  ) )
         RESULT data(read_entities_booksuppl_result)

        FAILED data(read_entities_failed).

        "READ ENTITIES OPERATIONS op_tab
        DATA:
      op_tab          TYPE abp_behv_retrievals_tab,
      read_dyn        TYPE TABLE FOR READ IMPORT zba_ab_travel,
      read_dyn_result TYPE TABLE FOR READ RESULT zba_ab_travel,
      rba_dyn         TYPE TABLE FOR READ IMPORT
                          zba_ab_travel\_Booking,
      rba_dyn_result  TYPE TABLE FOR READ RESULT
                          zba_ab_travel\_Booking,
      rba_dyn_link    TYPE TABLE FOR READ LINK
                          zba_ab_travel\_Booking.

      read_dyn = value #( ( %key-TravelId = '9004'
                            %control = value #(
                            TravelId = if_abap_behv=>mk-on
                            AgencyId = if_abap_behv=>mk-on
                            BeginDate = if_abap_behv=>mk-on
                            EndDate = if_abap_behv=>mk-on
                            description = if_abap_behv=>mk-on ) ) ).

      rba_dyn = VALUE #(
     ( %key-travelid = 9004
       %control = VALUE #( BookingId     = if_abap_behv=>mk-on
                             CarrierId    = if_abap_behv=>mk-on
                           ConnectionId   = if_abap_behv=>mk-on
                           FlightDate  = if_abap_behv=>mk-on
                           FlightPrice   = if_abap_behv=>mk-on
                           CurrencyCode   = if_abap_behv=>mk-on
                          ) ) ).

     op_tab = VALUE #(
       ( op = if_abap_behv=>op-r-read "op = 'R' also possible
         entity_name = 'ZBA_AB_TRAVEL'
         instances   = REF #( read_dyn )
         results = REF #( read_dyn_result ) )
       ( op = if_abap_behv=>op-r-read_ba "op = 'N' also possible
         entity_name = 'ZBA_AB_TRAVEL'
         sub_name = '_BOOKING'
         full = abap_true
         instances   = REF #( rba_dyn )
         results = REF #( rba_dyn_result )
         links = REF #( rba_dyn_link ) )
                  ).

        READ ENTITIES OPERATIONS op_tab FAILED FINAL(failed_dyn).
        SELECT * FROM @rba_dyn_result AS flight_tab3
            INTO TABLE @FINAL(read_by_assoc_dyn) UP TO 3 ROWS.
      ENDCASE.

  ENDMETHOD.
ENDCLASS.
