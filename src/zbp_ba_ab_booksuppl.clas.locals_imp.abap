CLASS lhc_BookSuppl DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR BookSuppl RESULT result.
    METHODS calctotalpricesuppl FOR DETERMINE ON MODIFY
      keys FOR booksuppl~calctotalpricesuppl.

ENDCLASS.

CLASS lhc_BookSuppl IMPLEMENTATION.

  METHOD get_instance_features.
    "use case: check the status of the current travel request
    "       If Rejected we should Create/ instance
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

        %update = COND #(
          WHEN overall_status = 'X'
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled
        )
      )
    ).

  ENDMETHOD.

  METHOD calcTotalPriceSuppl.
  MODIFY ENTITIES OF zba_ab_travel IN LOCAL MODE
    ENTITY Travel
    EXECUTE reCalcTotalPrice
    FROM CORRESPONDING #( keys ).
  ENDMETHOD.

ENDCLASS.
