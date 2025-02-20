package Queries;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    get_bib_ids_sql
    get_bib_detail_sql
    get_item_ids_sql
    get_item_detail_sql
    get_circ_ids_sql
    get_circ_detail_sql
    get_patron_ids_sql
    get_patron_detail_sql
    get_hold_ids_sql
    get_hold_detail_sql
);

# ----------------------------------------------------------
# get_bib_ids_sql - Return SQL for fetching BIB IDs
# ----------------------------------------------------------
sub get_bib_ids_sql {
    my ($full, $pgLibs) = @_;
    my $sql = qq{
       SELECT bre.id
       FROM biblio.record_entry bre
       JOIN asset.call_number acn ON (acn.record=bre.id AND NOT acn.deleted)
       WHERE acn.owning_lib IN ($pgLibs) AND ( NOT bre.deleted )
    };
    # If incremental run, filter by date
    $sql .= q{ AND (bre.edit_date > ? OR bre.create_date > ?) } unless $full;
    return $sql;
}

# ----------------------------------------------------------
# get_bib_detail_sql - Return SQL for fetching BIB details
# ----------------------------------------------------------
sub get_bib_detail_sql {
    return q{
        SELECT bre.id,
               i1.index_vector as isbn,
               i2.index_vector as upc,
               c.value as MatType,
               rmsr.pubdate,
               rmsr.publisher,
               rmsr.title,
               rmsr.author
        FROM biblio.record_entry bre
        JOIN reporter.materialized_simple_record rmsr ON rmsr.id = bre.id
        LEFT JOIN metabib.combined_identifier_field_entry i1 ON i1.record=bre.id AND i1.metabib_field=18
        LEFT JOIN metabib.combined_identifier_field_entry i2 ON i2.record=bre.id AND i2.metabib_field=20
        LEFT JOIN metabib.record_attr_vector_list v ON v.source=bre.id
        LEFT JOIN config.coded_value_map c ON c.id = ANY (v.vlist) AND ctype='icon_format'
        WHERE bre.id IN (:id_list)
        AND (bre.edit_date > ? OR bre.create_date > ?)
    };
}

# ----------------------------------------------------------
# get_item_ids_sql - Return SQL for fetching Item IDs
# ----------------------------------------------------------
sub get_item_ids_sql {
    my ($full, $pgLibs) = @_;
    my $sql = qq{
       SELECT ac.id
       FROM asset.copy ac
       JOIN asset.call_number acn ON (acn.id=ac.call_number AND NOT ac.deleted AND NOT acn.deleted)
       WHERE acn.owning_lib IN ($pgLibs) AND ( NOT ac.deleted )
    };
    # If incremental run, filter by date
    $sql .= q{ AND (ac.edit_date > ? OR ac.status_changed_time > ?) } unless $full;
    return $sql;
}

# ----------------------------------------------------------
# get_item_detail_sql - Return SQL for fetching Item details
# ----------------------------------------------------------
sub get_item_detail_sql {
    return q{
    SELECT
    ac.id as itemid,
    ac.barcode,
    i1.index_vector as isbn,
    i2.index_vector as upc,
    acn.record as bibid,
    acl.id as collection_code,
    ac.circ_modifier as mattype,
    aou_circ.shortname as branch_location,
    aou_owner.shortname as owning_location,
    btrim(regexp_replace(concat(acnp.label, ' ', acn.label, ' ', acns.label), '\\s{2,}', ' ')) as call_number,
    acl.name as shelf_location,
    ac.create_date,
    ccs.name as status,
    chkoutdate.lastcheckout,
    chkindate.lastcheckin,
    duedate.due,
    COALESCE(ytd.ytdcirccount, 0) as ytd_circ_count,
    COALESCE(circcount.tcirccount, 0) as circ_count
    FROM
    asset.copy ac
    JOIN asset.call_number acn ON (acn.id=ac.call_number )
    JOIN biblio.record_entry bre ON (bre.id=acn.record)
    LEFT JOIN reporter.materialized_simple_record rmsr ON (rmsr.id = bre.id)
    LEFT JOIN metabib.combined_identifier_field_entry i1 ON (i1.record=bre.id AND i1.metabib_field=18)
    LEFT JOIN metabib.combined_identifier_field_entry i2 ON (i2.record=bre.id AND i2.metabib_field=20)
    LEFT JOIN asset.copy_location acl ON (acl.id=ac.location)
    JOIN actor.org_unit aou_owner ON (acn.owning_lib=aou_owner.id)
    JOIN actor.org_unit aou_circ ON (ac.circ_lib=aou_circ.id)
    JOIN asset.call_number_prefix acnp ON (acnp.id=acn.prefix)
    JOIN asset.call_number_suffix acns ON (acns.id=acn.suffix)
    JOIN config.copy_status ccs ON (ccs.id=ac.status)
    LEFT JOIN lateral (
        SELECT COUNT(*) "ytdcirccount"
        FROM action.all_circulation acirc2
        WHERE acirc2.target_copy=ac.id
        AND date_part('year', acirc2.xact_start) = date_part('year', now())
    ) ytd ON (1=1)
    LEFT JOIN lateral (
        SELECT MAX(acirc2.xact_start) "lastcheckout"
        FROM action.all_circulation acirc2
        WHERE acirc2.target_copy=ac.id
        AND acirc2.xact_start IS NOT NULL
    ) chkoutdate ON (1=1)
    LEFT JOIN lateral (
        SELECT MAX(acirc2.xact_finish) "lastcheckin"
        FROM action.all_circulation acirc2
        WHERE acirc2.target_copy=ac.id
        AND acirc2.xact_finish IS NOT NULL
    ) chkindate ON (1=1)
    LEFT JOIN lateral (
        SELECT MAX(acirc2.due_date) "due"
        FROM action.all_circulation acirc2
        WHERE acirc2.target_copy=ac.id
        AND acirc2.xact_finish IS NULL
    ) duedate ON (1=1)
    LEFT JOIN lateral (
        SELECT COUNT(*) "tcirccount"
        FROM action.all_circulation acirc2
        WHERE acirc2.target_copy=ac.id
    ) circcount ON (1=1)
    WHERE ac.id IN (:id_list)
    AND (ac.edit_date > ? OR ac.status_changed_time > ?)
    };
}

# ----------------------------------------------------------
# get_circ_ids_sql - Return SQL for fetching Circulation IDs
# ----------------------------------------------------------
sub get_circ_ids_sql {
    my ($full, $pgLibs) = @_;
    my $sql = qq{
       SELECT acirc.id
       FROM action.all_circulation acirc
       JOIN asset.copy ac ON (ac.id=acirc.target_copy)
       JOIN asset.call_number acn ON (acn.id=ac.call_number AND NOT ac.deleted AND NOT acn.deleted)
       WHERE acn.owning_lib IN ($pgLibs)
    };
    # If incremental run, filter by date
    $sql .= q{ AND (acirc.xact_start > ?) } unless $full;
    return $sql;
}

# ----------------------------------------------------------
# get_circ_detail_sql - Return SQL for fetching Circulation details
# ----------------------------------------------------------
sub get_circ_detail_sql {
    return q{
       SELECT ac.id as itemid,
              ac.barcode,
              acn.record as bibid,
              TO_CHAR(acirc.xact_start, 'YYYY-MM-DD HH24:MI:SS') as checkout_date,
              aou_circ.shortname as checkout_branch,
              au.id as patron_id,
              acirc.due_date,
              acirc.checkin_time
       FROM action.circulation acirc
       JOIN asset.copy ac ON (ac.id=acirc.target_copy)
       JOIN asset.call_number acn ON (acn.id=ac.call_number AND NOT ac.deleted AND NOT acn.deleted)
       LEFT JOIN asset.copy_location acl ON (acl.id=ac.location)
       JOIN actor.usr au ON (acirc.usr=au.id)
       JOIN actor.org_unit aou_circ ON (acirc.circ_lib=aou_circ.id)
       WHERE acirc.id IN (:id_list)
       AND acirc.xact_start > ?
    };
}

# ----------------------------------------------------------
# get_patron_ids_sql - Return SQL for fetching Patron IDs
# ----------------------------------------------------------
sub get_patron_ids_sql {
    my ($full, $pgLibs) = @_;
    my $sql = qq{
       SELECT au.id
       FROM actor.usr au
       WHERE au.home_ou IN ($pgLibs) AND ( NOT au.deleted )
    };
    # If incremental run, filter by date
    $sql .= q{ AND (au.last_update_time > ?) } unless $full;
    return $sql;
}

# ----------------------------------------------------------
# get_patron_detail_sql - Return SQL for fetching Patron details
# ----------------------------------------------------------
sub get_patron_detail_sql {
    return q{
       SELECT au.id,
              au.expire_date,
              aou.shortname,
              au.create_date,
              p.name as patroncode,
              (CASE WHEN au.barred THEN 'barred' WHEN au.deleted THEN 'deleted' WHEN au.active THEN 'active' ELSE 'inactive' END) as status,
              (SELECT COUNT(*) FROM action.all_circulation acirc2 WHERE acirc2.usr=au.id AND date_part('year', xact_start) = date_part('year', now()) ) as ytd_circ_count,
              (SELECT COUNT(*) FROM action.all_circulation acirc2 WHERE acirc2.usr=au.id AND  xact_start>CURRENT_TIMESTAMP - interval '1 year') as prev_year_circ_count,
              (SELECT COUNT(*) FROM action.all_circulation acirc2 WHERE acirc2.usr=au.id ) as total_circ_count,
              (SELECT MAX(event_time) FROM actor.usr_activity aua WHERE aua.usr=au.id ) as last_activity,
              (SELECT MAX(xact_start) FROM action.all_circulation acirc2 WHERE acirc2.usr=au.id ) as last_checkout,
              aid.street1,
              aid.street2,
              aid.city,
              aid.state,
              aid.post_code
       FROM actor.usr au
       JOIN actor.org_unit aou ON (aou.id=au.home_ou)
       JOIN permission.grp_tree p ON (p.id=au.profile)
       LEFT JOIN LATERAL (SELECT auadd.street1,auadd.street2,auadd.city,auadd.state,auadd.post_code FROM actor.usr_address auadd
                          WHERE  auadd.id=(SELECT MAX(id) FROM actor.usr_address WHERE actor.usr_address.usr=au.id  )) aid ON 1=1
       WHERE au.id IN (:id_list)
       AND (au.create_date > ? OR au.last_update_time > ? OR au.last_update_time IS NULL)
    };
}

# ----------------------------------------------------------
# get_hold_ids_sql - Return SQL for fetching Hold IDs
# ----------------------------------------------------------
sub get_hold_ids_sql {
    my ($full, $pgLibs) = @_;
    my $sql = qq{
       SELECT ahr.id
       FROM action.hold_request ahr
       WHERE ahr.pickup_lib IN ($pgLibs) AND ( ahr.cancel_time IS NULL AND (ahr.expire_time IS NULL OR ahr.expire_time > NOW()) AND ahr.fulfillment_time IS NULL )
    };
    # If incremental run, filter by date
    $sql .= q{ AND (ahr.request_time > ?) } unless $full;
    return $sql;
}

# ----------------------------------------------------------
# get_hold_detail_sql - Return SQL for fetching Hold details
# ----------------------------------------------------------
sub get_hold_detail_sql {
    return q{
       SELECT
              (
                  CASE
                  WHEN ahr.hold_type='T' THEN ahr.target
                  WHEN ahr.hold_type='C' THEN ac_hold.record
                  WHEN ahr.hold_type='V' THEN acn_hold.record
                  WHEN ahr.hold_type='P' THEN acp_hold.record
                  WHEN ahr.hold_type='M' THEN mmr.master_record
                  ELSE -1
                  END
              ) as bibrecordid, ahr.pickup_lib, o.shortname
       FROM action.hold_request ahr
       JOIN actor.org_unit o ON o.id=ahr.pickup_lib
       LEFT JOIN biblio.record_entry bre ON(ahr.target=bre.id AND ahr.hold_type='T')
       LEFT JOIN (SELECT acn2.record,ac2.id FROM asset.call_number acn2 JOIN asset.copy ac2
                  ON ac2.call_number=acn2.id) ac_hold ON(ahr.target=ac_hold.id AND ahr.hold_type='C')
       LEFT JOIN (SELECT acn2.record,acn2.id FROM asset.call_number acn2 JOIN asset.copy ac2 ON ac2.call_number=acn2.id) acn_hold
       ON(ahr.target=acn_hold.id AND ahr.hold_type='V')
       LEFT JOIN (SELECT acn2.record,acp2.part as id FROM asset.call_number acn2 JOIN asset.copy ac2 ON ac2.call_number=acn2.id
                  JOIN asset.copy_part_map acp2 ON acp2.target_copy=ac2.id) acp_hold ON(ahr.target=acp_hold.id AND ahr.hold_type='P')
       LEFT JOIN metabib.metarecord mmr ON(mmr.id=ahr.target AND ahr.hold_type='M')
       WHERE ahr.id IN (:id_list)
       AND (ahr.request_time > ?)
    };
}

1;