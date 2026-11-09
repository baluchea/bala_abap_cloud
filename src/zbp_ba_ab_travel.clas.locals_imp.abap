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
    METHODS recalctotalprice FOR MODIFY
       keys FOR ACTION travel~recalctotalprice.
    METHODS calctotalprice FOR DETERMINE ON MODIFY
       keys FOR travel~calctotalprice.
    METHODS validateheaderdata FOR VALIDATE ON SAVE
      keys FOR travel~validateheaderdata.

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
    DATA travel_id_max TYPE /dmo/travel_id.
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
    TRY.
        cl_numberrange_runtime=>number_get(
          EXPORTING
            nr_range_nr       = '01'
            object            = CONV #( '/DMO/TRAVL' )
            quantity          = CONV #( lines( entities_wo_travelid ) )

          IMPORTING
            number            = DATA(number_range_key)
            returncode        = DATA(numer_range_return_code)
            returned_quantity = DATA(number_range_returned_quantity)
        ).
*        CATCH cx_nr_object_not_found.
      CATCH cx_number_ranges INTO DATA(lx_number_ranges).
        "Step 4 if there is a dump inside, we will just fill failed and reported
        reported-travel = VALUE #( BASE reported-travel FOR entity IN entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key %msg = lx_number_ranges )
                                    ).
        failed-travel = VALUE #( BASE failed-travel FOR entity IN entities_wo_travelid
                                    ( %cid = entity-%cid %key = entity-%key )
                                    ).
    ENDTRY.

    "Step 5 handle special cases if no. range exhaused , about to exhause
    CASE numer_range_return_code.
      WHEN '1'.
        "About to 99% number is finished - warning
        reported-travel = VALUE #( BASE reported-travel FOR entity IN entities_wo_travelid
                                   ( %cid = entity-%cid %key = entity-%key
                                     %msg = NEW /dmo/cm_flight_messages(
                                       textid = /dmo/cm_flight_messages=>number_range_depleted
                                       severity = if_abap_behv_message=>severity-warning )
                                   ) ).
      WHEN '2' OR 3.
        "last no was returned or no. range exhausted
        reported-travel = VALUE #( BASE reported-travel FOR entity IN entities_wo_travelid
                               ( %cid = entity-%cid %key = entity-%key
                                 %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>not_sufficient_numbers
                                   severity = if_abap_behv_message=>severity-warning )
                               ) ).
        failed-travel = VALUE #( BASE failed-travel FOR entity IN entities_wo_travelid
                                ( %cid = entity-%cid %key = entity-%key
                                %fail-cause = if_abap_behv=>cause-conflict )
                                ).
    ENDCASE.
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

    DATA max_booking_id TYPE /dmo/booking_id.

    ""Step 1: Get All the travel request and their bookings
    READ ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY travel BY  \_Booking
    FROM CORRESPONDING #( entities )
    LINK DATA(lt_bookings).


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
    ENDLOOP.

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

  METHOD reCalcTotalPrice.
    "---------------------------------------------------------------
    " Calculate Total Price
    " Travel BookingFee
    "   + Booking FlightPrice
    "   + Booking Supplement Price
    "
    " Amounts with different currencies are converted into the
    " Travel header currency.
    "---------------------------------------------------------------

    TYPES:
      BEGIN OF ty_total_cost,
        amount   TYPE /dmo/total_price,
        currency TYPE /dmo/currency_code,
      END OF ty_total_cost.

    DATA amounts_per_currencycode TYPE SORTED TABLE OF ty_total_cost
                                  WITH UNIQUE KEY currency.


    "---------------------------------------------------------------
    " Step 1: Read Travel header
    "---------------------------------------------------------------
    READ ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY Travel
        FIELDS (
          TravelId
          BookingFee
          CurrencyCode
          TotalPrice
        )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels)
        FAILED failed.


    "---------------------------------------------------------------
    " Step 2: Read Bookings
    "---------------------------------------------------------------
    READ ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY Travel BY \_Booking
        FIELDS (
          TravelId
          BookingId
          FlightPrice
          CurrencyCode
        )
        WITH CORRESPONDING #( travels )
        RESULT DATA(bookings)
        FAILED failed.


    "---------------------------------------------------------------
    " Step 3: Read Booking Supplements
    "---------------------------------------------------------------
    READ ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY Booking BY \_BookingSuppl
        FIELDS (
          TravelId
          BookingId
          Price
          CurrencyCode
        )
        WITH CORRESPONDING #( bookings )
        RESULT DATA(booking_supplements)
        FAILED failed.


    "---------------------------------------------------------------
    " Step 4: Remove records without currency
    "---------------------------------------------------------------
    DELETE travels
      WHERE CurrencyCode IS INITIAL.

    DELETE bookings
      WHERE CurrencyCode IS INITIAL.

    DELETE booking_supplements
      WHERE CurrencyCode IS INITIAL.


    "---------------------------------------------------------------
    " Step 5: Calculate TotalPrice separately for every Travel
    "---------------------------------------------------------------
    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).

      "Start fresh for every Travel
      CLEAR amounts_per_currencycode.

      DATA(header_currency) = <travel>-CurrencyCode.


      "-------------------------------------------------------------
      " Add Travel BookingFee
      "-------------------------------------------------------------
      COLLECT VALUE ty_total_cost(
        amount   = <travel>-BookingFee
        currency = <travel>-CurrencyCode
      ) INTO amounts_per_currencycode.


      "-------------------------------------------------------------
      " Add Booking FlightPrices
      "-------------------------------------------------------------
      LOOP AT bookings
           ASSIGNING FIELD-SYMBOL(<booking>)
           USING KEY id
           WHERE TravelId = <travel>-TravelId.

        COLLECT VALUE ty_total_cost(
          amount   = <booking>-FlightPrice
          currency = <booking>-CurrencyCode
        ) INTO amounts_per_currencycode.


        "-----------------------------------------------------------
        " Add Booking Supplement prices
        "-----------------------------------------------------------
        LOOP AT booking_supplements
             ASSIGNING FIELD-SYMBOL(<supplement>)
             USING KEY entity
             WHERE TravelId  = <booking>-TravelId
               AND BookingId = <booking>-BookingId.

          COLLECT VALUE ty_total_cost(
            amount   = <supplement>-Price
            currency = <supplement>-CurrencyCode
          ) INTO amounts_per_currencycode.

        ENDLOOP.

      ENDLOOP.


      "-------------------------------------------------------------
      " Step 6: Calculate TotalPrice in Travel header currency
      "-------------------------------------------------------------
      CLEAR <travel>-TotalPrice.

      LOOP AT amounts_per_currencycode
           ASSIGNING FIELD-SYMBOL(<amount_per_currency>).

        "Same currency -> no conversion required
        IF <amount_per_currency>-currency = header_currency.

          <travel>-TotalPrice +=
            <amount_per_currency>-amount.

        ELSE.

          "---------------------------------------------------------
          " Different currency -> convert to Travel currency
          "---------------------------------------------------------
          /dmo/cl_flight_amdp=>convert_currency(
            EXPORTING
              iv_amount =
                <amount_per_currency>-amount

              iv_currency_code_source =
                <amount_per_currency>-currency

              iv_currency_code_target =
                header_currency

              iv_exchange_rate_date =
                cl_abap_context_info=>get_system_date( )

            IMPORTING
              ev_amount =
                DATA(converted_amount)
          ).

          <travel>-TotalPrice += converted_amount.

        ENDIF.

      ENDLOOP.

    ENDLOOP.


    "---------------------------------------------------------------
    " Step 7: Update TotalPrice through EML
    "---------------------------------------------------------------
    MODIFY ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY Travel
        UPDATE FIELDS (
          TotalPrice
        )
        WITH CORRESPONDING #( travels )
      FAILED failed
      REPORTED reported.
  ENDMETHOD.

  METHOD calcTotalPrice.

    MODIFY ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel
    EXECUTE reCalcTotalPrice
    FROM CORRESPONDING #( keys ).


  ENDMETHOD.

  METHOD validateHeaderData.

 "------------------------------------------------------------
  " Step 1: Read incoming Travel data
  "------------------------------------------------------------
  READ ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel
      FIELDS ( AgencyId
               CustomerId
               BeginDate
               EndDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travel).


  "------------------------------------------------------------
  " Step 2: Prepare Customer and Agency ID tables
  "------------------------------------------------------------
  DATA lt_customers TYPE SORTED TABLE OF /dmo/customer
                    WITH UNIQUE KEY customer_id.

  DATA lt_agencies TYPE SORTED TABLE OF /dmo/agency
                   WITH UNIQUE KEY agency_id.


  "------------------------------------------------------------
  " Step 3: Extract unique Customer IDs
  "------------------------------------------------------------
  lt_customers = CORRESPONDING #(
    lt_travel
    DISCARDING DUPLICATES
    MAPPING
      customer_id = CustomerId
    EXCEPT * ).

  DELETE lt_customers
    WHERE customer_id IS INITIAL.


  " Extract unique Agency IDs
  lt_agencies = CORRESPONDING #(
    lt_travel
    DISCARDING DUPLICATES
    MAPPING
      agency_id = AgencyId
    EXCEPT * ).

  DELETE lt_agencies
    WHERE agency_id IS INITIAL.


  "------------------------------------------------------------
  " Step 4: Find existing Customers
  "------------------------------------------------------------
  IF lt_customers IS NOT INITIAL.

    SELECT FROM /dmo/customer
      FIELDS customer_id
      FOR ALL ENTRIES IN @lt_customers
      WHERE customer_id = @lt_customers-customer_id
      INTO TABLE @DATA(lt_cust_db).

  ENDIF.


  " Find existing Agencies
  IF lt_agencies IS NOT INITIAL.

    SELECT FROM /dmo/agency
      FIELDS agency_id
      FOR ALL ENTRIES IN @lt_agencies
      WHERE agency_id = @lt_agencies-agency_id
      INTO TABLE @DATA(lt_agency_db).

  ENDIF.


  "------------------------------------------------------------
  " Step 5: Validate each Travel instance
  "------------------------------------------------------------
  LOOP AT lt_travel INTO DATA(ls_travel).

    DATA(lv_failed) = abap_false.


    "----------------------------------------------------------
    " Customer ID is missing
    "----------------------------------------------------------
    IF ls_travel-CustomerId IS INITIAL.

      lv_failed = abap_true.

      APPEND VALUE #(
        %tky                = ls_travel-%tky
        %element-CustomerId = if_abap_behv=>mk-on
        %msg                = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text     = 'Customer ID must not be empty.' )
      ) TO reported-travel.


    "----------------------------------------------------------
    " Customer ID supplied, but it doesn't exist
    "----------------------------------------------------------
    ELSEIF NOT line_exists(
      lt_cust_db[
        customer_id = ls_travel-CustomerId
      ] ).

      lv_failed = abap_true.

      APPEND VALUE #(
        %tky                = ls_travel-%tky
        %element-CustomerId = if_abap_behv=>mk-on
        %msg                = NEW /dmo/cm_flight_messages(
          textid      = /dmo/cm_flight_messages=>customer_unkown
          customer_id = ls_travel-CustomerId
          severity    = if_abap_behv_message=>severity-error )
      ) TO reported-travel.

    ENDIF.


    "----------------------------------------------------------
    " Agency ID is missing
    "----------------------------------------------------------
    IF ls_travel-AgencyId IS INITIAL.

      lv_failed = abap_true.

      APPEND VALUE #(
        %tky              = ls_travel-%tky
        %element-AgencyId = if_abap_behv=>mk-on
        %msg              = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text     = 'Agency ID must not be empty.' )
      ) TO reported-travel.


    "----------------------------------------------------------
    " Agency ID supplied, but it doesn't exist
    "----------------------------------------------------------
    ELSEIF NOT line_exists(
      lt_agency_db[
        agency_id = ls_travel-AgencyId
      ] ).

      lv_failed = abap_true.

      APPEND VALUE #(
        %tky              = ls_travel-%tky
        %element-AgencyId = if_abap_behv=>mk-on
        %msg              = NEW /dmo/cm_flight_messages(
          textid    = /dmo/cm_flight_messages=>agency_unkown
          agency_id = ls_travel-AgencyId
          severity  = if_abap_behv_message=>severity-error )
      ) TO reported-travel.

    ENDIF.


    "----------------------------------------------------------
    " Add Travel to FAILED only once
    "----------------------------------------------------------
    IF lv_failed = abap_true.

      APPEND VALUE #(
        %tky = ls_travel-%tky
      ) TO failed-travel.

    ENDIF.

  ENDLOOP.
  ENDMETHOD.

ENDCLASS.
