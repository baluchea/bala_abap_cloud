CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      keys REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      REQUEST requested_authorizations FOR Travel RESULT result.
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

ENDCLASS.
