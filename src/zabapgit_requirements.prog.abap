*&---------------------------------------------------------------------*
*&  Include  zabapgit_requirements
*&---------------------------------------------------------------------*

"! Helper class for checking requirements / dependencies
*----------------------------------------------------------------------*
*       CLASS lcl_requirement_helper DEFINITION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_requirement_helper DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_requirement_status,
        met               TYPE abap_bool,
        component         TYPE dlvunit,
        description       TYPE text80,
        installed_release TYPE saprelease,
        installed_patch   TYPE sappatchlv,
        required_release  TYPE saprelease,
        required_patch    TYPE sappatchlv,
      END OF ty_requirement_status,
      ty_requirement_status_tt TYPE STANDARD TABLE OF ty_requirement_status WITH DEFAULT KEY.
    CLASS-METHODS:
      "! Check if the given requirements are met with user interaction
      "! <p>
      "! Shows a popup if requested and asks the user if he wants to continue if there are unmet
      "! requirements. If not an exception is raised.
      "! </p>
      "! @parameter it_requirements | The requirements to check
      "! @parameter iv_show_popup | Show popup with requirements
      "! @raising lcx_exception | Cancelled by user or internal error
      check_requirements IMPORTING it_requirements TYPE lcl_dot_abapgit=>ty_requirement_tt
                                   iv_show_popup   TYPE abap_bool DEFAULT abap_true
                         RAISING   lcx_exception,
      "! Get a table with information about each requirement
      "! @parameter it_requirements | Requirements
      "! @parameter rt_status | Result
      "! @raising lcx_exception | Internal error
      get_requirement_met_status IMPORTING it_requirements  TYPE lcl_dot_abapgit=>ty_requirement_tt
                                 RETURNING value(rt_status) TYPE ty_requirement_status_tt
                                 RAISING   lcx_exception.
  PRIVATE SECTION.
    CLASS-METHODS:
      show_requirement_popup IMPORTING it_requirements TYPE ty_requirement_status_tt
                             RAISING   lcx_exception,
      version_greater_or_equal IMPORTING is_status      TYPE ty_requirement_status
                               RETURNING value(rv_true) TYPE abap_bool.
ENDCLASS.                    "lcl_requirement_helper DEFINITION

*----------------------------------------------------------------------*
*       CLASS lcl_requirement_helper IMPLEMENTATION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_requirement_helper IMPLEMENTATION.
  METHOD check_requirements.
    DATA: lt_met_status TYPE ty_requirement_status_tt,
          lv_answer     TYPE c LENGTH 1.

    lt_met_status = get_requirement_met_status( it_requirements ).

    IF iv_show_popup = abap_true.
      show_requirement_popup( lt_met_status ).
    ENDIF.

    LOOP AT lt_met_status TRANSPORTING NO FIELDS WHERE met = abap_false.
      EXIT.
    ENDLOOP.

    IF sy-subrc = 0.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING
          text_question = 'The project has unmet requirements. Do you want to continue?'
        IMPORTING
          answer        = lv_answer.
      IF lv_answer <> '1'.
        lcx_exception=>raise( 'Cancelling because of unmet requirements.' ).
      ENDIF.
    ENDIF.
  ENDMETHOD.                    "check_requirements

  METHOD get_requirement_met_status.
    DATA: lt_installed TYPE STANDARD TABLE OF cvers_sdu.
    FIELD-SYMBOLS: <ls_requirement>    TYPE lcl_dot_abapgit=>ty_requirement,
                   <ls_status>         TYPE ty_requirement_status,
                   <ls_installed_comp> TYPE cvers_sdu.

    CALL FUNCTION 'DELIVERY_GET_INSTALLED_COMPS'
      TABLES
        tt_comptab       = lt_installed
      EXCEPTIONS
        no_release_found = 1
        OTHERS           = 2.
    IF sy-subrc <> 0.
      lcx_exception=>raise( |Error from DELIVERY_GET_INSTALLED_COMPS { sy-subrc }| ) ##no_text.
    ENDIF.

    LOOP AT it_requirements ASSIGNING <ls_requirement>.
      APPEND INITIAL LINE TO rt_status ASSIGNING <ls_status>.
      <ls_status>-component = <ls_requirement>-component.
      <ls_status>-required_release = <ls_requirement>-min_release.
      <ls_status>-required_patch = <ls_requirement>-min_patch.

      READ TABLE lt_installed WITH KEY component = <ls_requirement>-component
                              ASSIGNING <ls_installed_comp>.
      IF sy-subrc = 0.
        " Component is installed, requirement is met if the installed version is greater or equal
        " to the required one.
        <ls_status>-installed_release = <ls_installed_comp>-release.
        <ls_status>-installed_patch = <ls_installed_comp>-extrelease.
        <ls_status>-description = <ls_installed_comp>-desc_text.
        <ls_status>-met = version_greater_or_equal( <ls_status> ).
      ELSE.
        " Component is not installed at all
        <ls_status>-met = abap_false.
      ENDIF.

      UNASSIGN <ls_installed_comp>.
    ENDLOOP.
  ENDMETHOD.                    "get_requirement_met_status

  METHOD version_greater_or_equal.
    DATA: lv_number TYPE numc4 ##NEEDED.

    TRY.
        MOVE EXACT: is_status-installed_release TO lv_number,
                    is_status-installed_patch   TO lv_number,
                    is_status-required_release  TO lv_number,
                    is_status-required_patch    TO lv_number.
      CATCH cx_sy_conversion_error.
        " Cannot compare by number, assume requirement not fullfilled (user can force install
        " anyways if this was an error)
        rv_true = abap_false.
        RETURN.
    ENDTRY.

    " Versions are comparable by number, compare release and if necessary patch level
    IF is_status-installed_release > is_status-required_release
       OR ( is_status-installed_release = is_status-required_release
            AND ( is_status-required_patch IS INITIAL OR
                  is_status-installed_patch >= is_status-required_patch ) ).

      rv_true = abap_true.
    ENDIF.
  ENDMETHOD.                    "version_greater_or_equal

  METHOD show_requirement_popup.

    TYPES: BEGIN OF lty_color_line,
             color TYPE lvc_t_scol.
            INCLUDE TYPE ty_requirement_status.
    TYPES: END OF lty_color_line,
    lty_color_tab TYPE STANDARD TABLE OF lty_color_line WITH DEFAULT KEY.

    DATA: lo_alv            TYPE REF TO cl_salv_table,
          lo_column         TYPE REF TO cl_salv_column,
          lo_columns        TYPE REF TO cl_salv_columns_table,
          lt_color_table    TYPE lty_color_tab,
          lt_color_negative TYPE lvc_t_scol,
          lt_color_positive TYPE lvc_t_scol,
          ls_color          TYPE lvc_s_scol,
          lx_ex             TYPE REF TO cx_root.

    FIELD-SYMBOLS: <ls_line> TYPE lty_color_line,
                   <ls_requirement> LIKE LINE OF it_requirements.


    ls_color-color-col = col_negative.
    APPEND ls_color TO lt_color_negative.

    ls_color-color-col = col_positive.
    APPEND ls_color TO lt_color_positive.

    CLEAR ls_color.

    LOOP AT it_requirements ASSIGNING <ls_requirement>.
      APPEND INITIAL LINE TO lt_color_table ASSIGNING <ls_line>.
      MOVE-CORRESPONDING <ls_requirement> TO <ls_line>.
    ENDLOOP.

    LOOP AT lt_color_table ASSIGNING <ls_line>.
      IF <ls_line>-met = abap_false.
        <ls_line>-color = lt_color_negative.
      ELSE.
        <ls_line>-color = lt_color_positive.
      ENDIF.
    ENDLOOP.
    UNASSIGN <ls_line>.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                                CHANGING t_table       = lt_color_table ).

        lo_columns = lo_alv->get_columns( ).
        lo_columns->get_column( 'MET' )->set_short_text( 'Met' ).
        lo_columns->set_color_column( 'COLOR' ).
        lo_columns->set_optimize( ).

        lo_column = lo_columns->get_column( 'REQUIRED_RELEASE' ).
*        lo_column->set_fixed_header_text( 'S' ).
        lo_column->set_short_text( 'Req. Rel.' ).

        lo_column = lo_columns->get_column( 'REQUIRED_PATCH' ).
*        lo_column->set_fixed_header_text( 'S' ).
        lo_column->set_short_text( 'Req. SP L.' ).

        lo_alv->set_screen_popup( start_column = 30
                                  end_column   = 100
                                  start_line   = 10
                                  end_line     = 20 ).
        lo_alv->get_display_settings( )->set_list_header( 'Requirements' ).
        lo_alv->display( ).

      CATCH cx_salv_msg cx_salv_not_found cx_salv_data_error INTO lx_ex.
        RAISE EXCEPTION TYPE lcx_exception
          EXPORTING
            iv_text     = lx_ex->get_text( )
            ix_previous = lx_ex.
    ENDTRY.
  ENDMETHOD.                    "show_requirement_popup
ENDCLASS.                    "lcl_requirement_helper IMPLEMENTATION
