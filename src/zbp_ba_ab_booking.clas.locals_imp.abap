CLASS lhc_Booking DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS earlynumbering_cba_Bookingsupp FOR NUMBERING
       entities FOR CREATE Booking\_Bookingsuppl.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Booking RESULT result.
    METHODS calctotalpricebook FOR DETERMINE ON MODIFY
      keys FOR booking~calctotalpricebook.

ENDCLASS.

CLASS lhc_Booking IMPLEMENTATION.

  METHOD earlynumbering_cba_Bookingsupp.
    DATA max_book_suppl_id TYPE /dmo/booking_supplement_id.

        " Step 1: Read existing booking supplements
        READ ENTITIES OF zba_ab_travel IN LOCAL MODE
          ENTITY booking BY \_BookingSuppl
          FROM CORRESPONDING #( entities )
          LINK DATA(lt_booking_suppl).

        " Step 2: Group requests by TravelId and BookingId
        LOOP AT entities ASSIGNING FIELD-SYMBOL(<entity>)
             GROUP BY (
               TravelId  = <entity>-TravelId
               BookingId = <entity>-BookingId
             )
             ASSIGNING FIELD-SYMBOL(<booking_group>).

          " BookingSupplementId is determined separately for every booking
          CLEAR max_book_suppl_id.

          " Step 3: Get the highest existing BookingSupplementId
          max_book_suppl_id = REDUCE #(
            INIT max_id = max_book_suppl_id

            FOR book_suppl IN lt_booking_suppl USING KEY entity
            WHERE (
              source-TravelId  = <booking_group>-TravelId AND
              source-BookingId = <booking_group>-BookingId
            )

            NEXT max_id = COND #(
              WHEN book_suppl-target-BookingSupplementId > max_id
              THEN book_suppl-target-BookingSupplementId
              ELSE max_id
            )
          ).

          " Step 4: Also consider IDs supplied in the incoming request
          LOOP AT GROUP <booking_group>
               ASSIGNING FIELD-SYMBOL(<booking>).

            max_book_suppl_id = REDUCE #(
              INIT max_id = max_book_suppl_id

              FOR target IN <booking>-%target

              NEXT max_id = COND #(
                WHEN target-BookingSupplementId > max_id
                THEN target-BookingSupplementId
                ELSE max_id
              )
            ).

      ENDLOOP.

      " Step 5: Map requests and generate missing supplement IDs
      LOOP AT GROUP <booking_group>
           ASSIGNING FIELD-SYMBOL(<booking_to_map>).

        LOOP AT <booking_to_map>-%target
             ASSIGNING FIELD-SYMBOL(<book_suppl>).

          APPEND CORRESPONDING #( <book_suppl> )
            TO mapped-booksuppl
            ASSIGNING FIELD-SYMBOL(<mapped_book_suppl>).

          IF <mapped_book_suppl>-BookingSupplementId IS INITIAL.
            max_book_suppl_id += 1.
            <mapped_book_suppl>-BookingSupplementId = max_book_suppl_id.
          ENDIF.

        ENDLOOP.

      ENDLOOP.

    ENDLOOP.
  ENDMETHOD.

  METHOD get_instance_features.
    "use case: check the status of the current travel request
    "       If Rejected we should EDIT Booking instance
    "Step 1: EML to read the Travel Status

    " Step 1: Read parent Travel status for the Booking keys
    READ ENTITIES OF zba_ab_travel IN LOCAL MODE
      ENTITY travel
        FIELDS ( TravelId OverallStatus )
        WITH VALUE #(
          FOR key IN keys
          ( %key-TravelId = key-TravelId )
        )
      RESULT DATA(lt_travel)
      FAILED DATA(lt_failed).

    " Step 2: Set update feature for every requested Booking
    result = VALUE #(
      FOR key IN keys

      LET overall_status = VALUE #(
        lt_travel[
          KEY entity
          TravelId = key-TravelId
        ]-OverallStatus OPTIONAL
      )

      IN
      (
        %tky = key-%tky
        %assoc-_BookingSuppl = COND #(
          WHEN overall_status = 'X'
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled
        )
        %update = COND #(
          WHEN overall_status = 'X'
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled
        )
      )
    ).

  ENDMETHOD.

  METHOD calcTotalPriceBook.

    MODIFY ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel
    EXECUTE reCalcTotalPrice
    FROM CORRESPONDING #( keys ).

  ENDMETHOD.

ENDCLASS.
