CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      keys REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      REQUEST requested_authorizations FOR Travel RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Travel RESULT result.
    METHODS copytravel FOR MODIFY
      keys FOR ACTION travel~copytravel.

    METHODS earlynumbering_cba_Booking FOR NUMBERING
      entities FOR CREATE Travel\_Booking.

    METHODS earlynumbering_create FOR NUMBERING
       entities FOR CREATE Travel.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD earlynumbering_create.
    DATA travel_id_max type /dmo/travel_id.
    "Step 1 Ensure the User Id not passed by the use so we generate TravelID
    mapped-travel = VALUE #(
                     FOR entity IN entities
                   WHERE ( TravelId IS NOT INITIAL )
                   ( CORRESPONDING #( entity ) ) ).
    "Step 2 Lets take all the travel data in another Copy
    "       Filter out record which has travel Id, only keep where travel id is blank
*    If we need to use sort this tbale before using Filter
*    DATA(entities_wo_travelid) = FILTER #( entities
*                                      WHERE TravelId IS INITIAL ).

    DATA(entities_wo_travelid) = entities.
    DELETE entities_wo_travelid WHERE TravelId IS NOT INITIAL.

    "Step 3 Lets use SNRO number rage generator
    "" example current no 422 , i want 3 = 426, 426-3 = 423
    "" 423+1 = 424, 424+1 = 425, 425+1 = 426
    try.
        cl_numberrange_runtime=>number_get(
          EXPORTING
            nr_range_nr       = '01'
            object            = CONV #( '/DMO/TRAVL' )
            quantity          = CONV #( lines( entities_wo_travelid ) )

          IMPORTING
            number            = data(number_range_key)
            returncode        = data(numer_range_return_code)
            returned_quantity = data(number_range_returned_quantity)
        ).
*        CATCH cx_nr_object_not_found.
        CATCH cx_number_ranges into data(lx_number_ranges).
     "Step 4 if there is a dump inside, we will just fill failed and reported
        reported-travel = value #( BASE reported-travel for entity in entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key %msg = lx_number_ranges )
                                    ).
        failed-travel = value #( base failed-travel for entity in entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key )
                                    ).
    endtry.

    "Step 5 handle special cases if no. range exhaused , about to exhause
     case numer_range_return_code.
        when '1'.
        "About to 99% number is finished - warning
         reported-travel = value #( BASE reported-travel for entity in entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key
                                      %msg = new /dmo/cm_flight_messages(
                                        textid = /dmo/cm_flight_messages=>number_range_depleted
                                        severity = if_abap_behv_message=>severity-warning )
                                    ) ).
        when '2' or 3.
            "last no was returned or no. range exhausted
             reported-travel = value #( BASE reported-travel for entity in entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key
                                      %msg = new /dmo/cm_flight_messages(
                                        textid = /dmo/cm_flight_messages=>not_sufficient_numbers
                                        severity = if_abap_behv_message=>severity-warning )
                                    ) ).
            failed-travel = value #( base failed-travel for entity in entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key
                                    %fail-cause = if_abap_behv=>cause-conflict )
                                    ).
     endcase.
     "Final check for All number
        ASSERT number_range_returned_quantity = lines( entities_wo_travelid ).

     "Step 7 loop over the incoming data and assign the travel id by incrementing it send
     "the data wrapped to rap framework
    travel_id_max = number_range_key - number_range_returned_quantity.

LOOP AT entities_wo_travelid ASSIGNING FIELD-SYMBOL(<entity>).

  travel_id_max += 1.
  <entity>-TravelId = travel_id_max.

  APPEND VALUE #(
    %cid      = <entity>-%cid
    %key      = <entity>-%key
  ) TO mapped-travel.

ENDLOOP.

  ENDMETHOD.

  METHOD earlynumbering_cba_Booking.

     data max_booking_id type /dmo/booking_id.

     ""Step 1: Get All the travel request and their bookings
     read ENTITIES OF zba_ab_travel in LOCAL MODE
     ENTITY travel by  \_Booking
     from CORRESPONDING #( entities )
     LINK data(lt_bookings).


     ""Step 2: Cases to handle for Assigning unique Booking ID
    "1001, 1002, 1005
     " Determine maximum already-created BookingId for this TravelId
     LOOP AT entities ASSIGNING FIELD-SYMBOL(<travel_group>)
                    GROUP BY <travel_group>-TravelId.
        max_booking_id = REDUCE #(
        INIT max = max_booking_id
        FOR booking IN lt_bookings USING KEY entity
        WHERE ( source-TravelId = <travel_group>-TravelId )
        NEXT max = COND #(
          WHEN booking-target-BookingId > max
          THEN booking-target-BookingId
          ELSE max
        )
      ).
    endloop.

     ""Step 4: Loop over all the entities of travel with same travel id and increment the max booking id

     LOOP AT entities ASSIGNING FIELD-SYMBOL(<travel>)
     GROUP BY <travel>-TravelId.

     LOOP AT <travel>-%target ASSIGNING FIELD-SYMBOL(<booking>).

        APPEND CORRESPONDING #( <booking> )
          TO mapped-booking
          ASSIGNING FIELD-SYMBOL(<mapped_booking>).

        IF <mapped_booking>-BookingId IS INITIAL.
          max_booking_id += 10.
          <mapped_booking>-BookingId = max_booking_id.
       ENDIF.

     ENDLOOP.

ENDLOOP.

  ENDMETHOD.

  METHOD get_instance_features.

    "use case: check the status of the current travel request
    "       If cancelled we should disable Booking creation
    "Step 1: EML to read the Travel Status

        " Step 1: Read the Travel status
     READ ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY travel
        FIELDS ( TravelId OverallStatus )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_travel)
      FAILED DATA(lt_failed).

    " Step 2: Determine whether Booking creation is allowed
    result = VALUE #(
      FOR travel IN lt_travel
      (
        %tky = travel-%tky

        %assoc-_Booking = COND #(
          WHEN travel-OverallStatus = 'X'
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled
        )
      )
    ).
  ENDMETHOD.

  METHOD copyTravel.

  "-------------------------------------------------------------
  " Deep copy:
  " Travel -> Bookings -> Booking Supplements
  "-------------------------------------------------------------

  DATA:
    travels       TYPE TABLE FOR CREATE
                    zba_ab_travel\\Travel,

    bookings_cba  TYPE TABLE FOR CREATE
                    zba_ab_travel\\Travel\_Booking,

    booksuppl_cba TYPE TABLE FOR CREATE
                    zba_ab_travel\\Booking\_BookingSuppl.


  "-------------------------------------------------------------
  " Step 1: Validate incoming CIDs
  "-------------------------------------------------------------
  ASSERT NOT line_exists( keys[ %cid = '' ] ).


  "-------------------------------------------------------------
  " Step 2: Read the selected Travels
  "-------------------------------------------------------------

  READ ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel
      ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(travel_read_result)
      FAILED failed
      REPORTED reported.


  "-------------------------------------------------------------
  " Step 3: Read the associated Bookings
  "-------------------------------------------------------------
  READ ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel BY \_Booking
      ALL FIELDS
      WITH CORRESPONDING #( travel_read_result )
      RESULT DATA(book_read_result)
      FAILED failed
      REPORTED reported.


  "-------------------------------------------------------------
  " Step 4: Read the associated Booking Supplements
  "-------------------------------------------------------------
  READ ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Booking BY \_BookingSuppl
      ALL FIELDS
      WITH CORRESPONDING #( book_read_result )
      RESULT DATA(booksuppl_read_result)
      FAILED failed
      REPORTED reported.


  "-------------------------------------------------------------
  " Step 5: Prepare the deep-copy data
  "-------------------------------------------------------------
  LOOP AT travel_read_result
       ASSIGNING FIELD-SYMBOL(<travel>).

    DATA(travel_cid) =
      keys[ KEY entity
            %tky = <travel>-%tky ]-%cid.


    "-----------------------------------------------------------
    " Prepare new Travel
    "
    "TravelId must not be copied because early numbering
    "generates a new TravelId.
    "-----------------------------------------------------------
    APPEND VALUE #(
      %cid = travel_cid

      %data = CORRESPONDING #(
        <travel>
        EXCEPT
          TravelId
      )
    ) TO travels
      ASSIGNING FIELD-SYMBOL(<new_travel>).


    <new_travel>-BeginDate =
      cl_abap_context_info=>get_system_date( ).

    <new_travel>-EndDate =
      cl_abap_context_info=>get_system_date( ) + 30.

    <new_travel>-OverallStatus = 'O'.


    "-----------------------------------------------------------
    " Prepare Travel-to-Booking CBA structure
    "-----------------------------------------------------------
    APPEND VALUE #(
      %cid_ref = travel_cid
    ) TO bookings_cba
      ASSIGNING FIELD-SYMBOL(<booking_cba>).


    "-----------------------------------------------------------
    " Copy Bookings belonging to the current Travel
    "-----------------------------------------------------------
    LOOP AT book_read_result
         ASSIGNING FIELD-SYMBOL(<booking>)
         USING KEY id
         WHERE TravelId = <travel>-TravelId.

      DATA(booking_cid) =
        |{ travel_cid }_{ <booking>-BookingId }|.


      "---------------------------------------------------------
      " Prepare new Booking
      "
      "Important:
      "TravelId and BookingId must not be copied.
      "
      "TravelId comes from the association.
      "BookingId comes from early numbering.
      "---------------------------------------------------------
      APPEND VALUE #(
        %cid = booking_cid

        %data = CORRESPONDING #(
          <booking>
          EXCEPT
            TravelId
            BookingId
        )
      ) TO <booking_cba>-%target
        ASSIGNING FIELD-SYMBOL(<new_booking>).


      <new_booking>-BookingStatus = 'N'.


      "---------------------------------------------------------
      " Prepare Booking-to-Supplement CBA structure
      "---------------------------------------------------------
      APPEND VALUE #(
        %cid_ref = booking_cid
      ) TO booksuppl_cba
        ASSIGNING FIELD-SYMBOL(<booksuppl_cba>).


      "---------------------------------------------------------
      " Copy Supplements belonging to the current Booking
      "---------------------------------------------------------
      LOOP AT booksuppl_read_result
           ASSIGNING FIELD-SYMBOL(<book_suppl>)
           USING KEY entity
           WHERE TravelId  = <travel>-TravelId
             AND BookingId = <booking>-BookingId.

        DATA(supplement_cid) =
          |{ booking_cid }_{
             <book_suppl>-BookingSupplementId }|.


        "-------------------------------------------------------
        " Prepare new Booking Supplement
        "
        "TravelId and BookingId come from the association.
        "The existing BookingSupplementId is preserved because
        "no separate early-numbering method is shown for it.
        "-------------------------------------------------------
        APPEND VALUE #(
          %cid = supplement_cid

          %data = CORRESPONDING #(
            <book_suppl>
            EXCEPT
              TravelId
              BookingId
          )
        ) TO <booksuppl_cba>-%target.

      ENDLOOP.

    ENDLOOP.

  ENDLOOP.


  "-------------------------------------------------------------
  " Step 6: Create the complete hierarchy
  "-------------------------------------------------------------
  MODIFY ENTITIES OF zba_ab_travel IN LOCAL MODE

    ENTITY Travel
      CREATE FIELDS (
        AgencyId
        CustomerId
        BeginDate
        EndDate
        BookingFee
        TotalPrice
        CurrencyCode
        OverallStatus
      )
      WITH travels

      CREATE BY \_Booking
        FIELDS (
          BookingDate
          CustomerId
          CarrierId
          ConnectionId
          FlightDate
          FlightPrice
          CurrencyCode
          BookingStatus
        )
        WITH bookings_cba

    ENTITY Booking
      CREATE BY \_BookingSuppl
        FIELDS (
          BookingSupplementId
          SupplementId
          Price
          CurrencyCode
        )
        WITH booksuppl_cba

    MAPPED mapped
    FAILED failed
    REPORTED reported.


  ENDMETHOD.

ENDCLASS.
