CLASS zcx_bulk_transport DEFINITION
PUBLIC
INHERITING FROM cx_no_check
CREATE PUBLIC.

PUBLIC SECTION.
DATA detail TYPE string READ-ONLY.

METHODS constructor
  IMPORTING
    iv_detail TYPE string.

PROTECTED SECTION.

ENDCLASS.

CLASS zcx_bulk_transport IMPLEMENTATION.

METHOD constructor.
super->constructor( ).
detail = iv_detail.
ENDMETHOD.

ENDCLASS.
