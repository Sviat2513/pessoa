xquery version "3.0";

module namespace search="http://localhost:8080/exist/apps/pessoa/search";

import module namespace templates="http://exist-db.org/xquery/templates" at "templates.xql";
import module namespace config="http://localhost:8080/exist/apps/pessoa/config" at "config.xqm";
import module namespace lists="http://localhost:8080/exist/apps/pessoa/lists" at "lists.xqm";
import module namespace doc="http://localhost:8080/exist/apps/pessoa/doc" at "doc.xqm";
import module namespace helpers="http://localhost:8080/exist/apps/pessoa/helpers" at "helpers.xqm";
import module namespace page="http://localhost:8080/exist/apps/pessoa/page" at "page.xqm";

import module namespace kwic="http://exist-db.org/xquery/kwic";
declare namespace util="http://exist-db.org/xquery/util";
declare namespace text="http://exist-db.org/xquery/text";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace tei="http://www.tei-c.org/ns/1.0";

(:  Profi Suche :)
declare %templates:wrap function search:profisearch($node as node(), $model as map(*), $term as xs:string?) as map(*) {
        (: Erstellung der Kollektion, sortiert ob "Publiziert" oder "Nicht Publiziert" :)
        let $db := search:set_db()
        let $dbase :=  if($term != "" ) then collection($db)//tei:TEI[ft:query(.,$term)]
                       else if(search:get-parameters("lang_ao") = "or") 
                       then search:lang_or($db)
                       else search:lang_and($db)
        (: Unterscheidung nach den Sprachen, ob "Und" oder "ODER" :)
       let $r_lang := if($term != "" and search:get-parameters("search")!= "simple") then 
                      if (search:get-parameters("lang_ao") ="or")
                        then search:lang_or_term($dbase)
                        else (search:lang_and_term($dbase,"unpublished"),search:lang_and_term($dbase,"published"))
                      else $dbase
        let $dbase := $r_lang
        (: Sortierung nach Genre :)
        let $r_genre := if(search:get-parameters("genre")!="") then search:search_range("genre",$dbase)
                        else $dbase                   
        let $dbase := $r_genre
        (:Suche nach "Erwähnten" Rollen:)
        let $r_mention := if(search:get-parameters("notional")="mentioned" and search:get-parameters("person")!="") then search:author_build($dbase)
                        else $dbase
        let $dbase := $r_mention
        let $r_real := if(search:get-parameters("notional") ="real" and search:get-parameters("person")!="") then search:search_range("person",$dbase)
                        else $dbase
        let $dbase := $r_real                
     
        (: Datumssuche :)
        let $r_date := if(search:get-parameters("before") != "" or search:get-parameters("after") != "") then search:date_build($dbase)
                        else $dbase
        let $dbase := $r_date
        (: Volltext Suche :)                

        let $r_all := ($r_genre,$r_mention,$r_real,$r_date)
       
        return map{
            "r_union"   := search:result_union($dbase),
            "r_dbase"   := $dbase,
            "query"     := $term
        }
        
};




declare function search:set_db() as xs:string+ {
        let $result :=       if(search:get-parameters("release") = "unpublished")    then "/db/apps/pessoa/data/doc"
                             else if(search:get-parameters("release") = "published" )  then "/db/apps/pessoa/data/pub"
                             else ("/db/apps/pessoa/data/doc","/db/apps/pessoa/data/pub")
                            
                   return $result
};

(: Funtkion um die Parameter rauszufiltern:)
declare function search:get-parameters($key as xs:string) as xs:string* {
    for $hit in request:get-parameter-names()
        return if($hit=$key) then request:get-parameter($hit,'')
                else ()
};

(: ODER FUNKTION : FIltert die Sprache, TERM :)
declare function search:lang_or_term($db as node()*) as node()* {
    for $hit in search:get-parameters("lang")
        let $para := ("mainLang","otherLang","Lang")
        for $match in $para
                let $search_terms := concat('("',$match,'"),"',$hit,'"')
                let $search_funk := concat("//range:field-contains(",$search_terms,")")
                let $search_build := concat("$db",$search_funk)
            return util:eval($search_build)
};

(: UND FUNKTION : Filtert die Sprache, TERM:)

declare function search:lang_and_term($db as node()*, $step as xs:string) as node()* {
        if(search:get-parameters("release")="unpublished" and $step = "unpublished") then
            for $match in search:lang_build_para_doc("lang")
                let $build_funk := concat("//range:field-contains(",$match,")")
                let $build_search := concat("$db",$build_funk) 
                return util:eval($build_search) 
        else if (search:get-parameters("release")="published" and $step = "published") then 
            for $match in search:get-parameters("lang")
            let $build_funk := concat("//range:field-contains('lang','",$match,"')")
            let $build_search := concat("$db",$build_funk)
            return util:eval($build_search)  
        else ()
};
(: ODER FUNTKION : Filtert die Sprache :) 
declare function search:lang_or ($db as xs:string+) as node()*{
    for $match in $db
        let $result := if(search:get-parameters("release") != "either") then  search:lang_filter_or($match,"")
                      else if(search:get-parameters("release") = "either") then 
                            if($match = "/db/apps/pessoa/data/doc") then search:lang_filter_or($match,"unpublished")
                            else if ($match = "/db/apps/pessoa/data/pub") then search:lang_filter_or($match, "published")
                            else()
                       else ()
        return $result
};

declare function search:lang_filter_or($db as xs:string, $step as xs:string?) as node()* {
    if(search:get-parameters("release")="unpublished" or $step = "unpublished") then
        for $hit in search:get-parameters("lang")
            let $para := ("mainLang","otherLang")
            for $match in $para
                let $search_terms := concat('("',$match,'"),"',$hit,'"')
                let $search_funk := concat("//range:field-contains(",$search_terms,")")
                let $search_build := concat("collection($db)",$search_funk)
            return util:eval($search_build) 
        else if (search:get-parameters("release")="published" or $step = "published") then 
            for $hit in search:get-parameters("lang")
                let $search_terms := concat('("lang"),"',$hit,'"')
                let $search_funk := concat("//range:field-contains(",$search_terms,")")
                let $search_build := concat("collection($db)",$search_funk)
            return util:eval($search_build) 
        else ()
};

(: START UND FUNKTION : Filtert die Sprache :)

declare function search:lang_and($db as xs:string+) as node()* {
    for $match in $db 
        let $result := if(search:get-parameters("release") != "either") then  search:lang_filter_and($match,"")
                      else if(search:get-parameters("release") = "either") then 
                            if($match = "/db/apps/pessoa/data/doc") then search:lang_filter_and($match,"unpublished")
                            else if ($match = "/db/apps/pessoa/data/pub") then search:lang_filter_and($match, "published")
                            else()
                       else ()
                       (:(search:lang_filter_and($match,"non_public"),search:lang_filter_and($match, "public")):)
        return $result
};

declare function search:lang_filter_and($db as xs:string, $step as xs:string?) as node()* {
        if(search:get-parameters("release")="unpublished" or $step = "unpublished") then
            for $match in search:lang_build_para_doc("lang")
                let $build_funk := concat("//range:field-contains(",$match,")")
                let $build_search := concat("collection($db)",$build_funk) 
                return util:eval($build_search) 
        else if (search:get-parameters("release")="published" or $step = "published") then 
            for $match in search:get-parameters("lang")
            let $build_funk := concat("//range:field-contains('lang','",$match,"')")
            let $build_search := concat("collection($db)",$build_funk)
            return util:eval($build_search)  
        else ()
};
declare function search:lang_build_para_doc ($para as xs:string) as xs:string* {
    for $hit in search:get-parameters($para)
     (: let $parameters :=  search:get-parameters($para):)
        let $result := concat('("',
        string-join(search:lang_build_para_doc_ex(search:get-parameters($para),$hit),
        '","'),'"),"',
        string-join(search:get-parameters("lang"),'","'),'"')
        return $result
};

declare function search:lang_build_para_doc_ex($para as xs:string+, $hit as xs:string) as xs:string* {
        for $other in $para
            let $result := if($other = $hit) then "mainLang" else "otherLang"
            return $result
};
(: Sprach Filter END:)

(: Query Suche :)
declare function search:search_query($para as xs:string, $db as node()*) as node()* {
    for $hit in search:get-parameters($para)
        let $hit := if($para = "genre") then replace($hit, "_", " ")
                    else $hit
        
            let $query := <query><bool><term occur="must">{$hit}</term></bool></query>
            let $search_funk := "[ft:query(.,$query)]"
            let $search_build := concat("collection($db)//tei:msItemStruct",$search_funk) 
            return util:eval($search_build)
};
(: Range Suche :)
declare function search:search_range($para as xs:string, $db as node()*) as node()* {
    for $hit in search:get-parameters($para)    
     (:   let $para := if($para = "person")then  "author" else () :)
        let $search_terms := concat('("',$para,'"),"',$hit,'"')
        let $search_funk := concat("//range:field-eq(",$search_terms,")")
        let $search_build := concat("$db",$search_funk)
        return util:eval($search_build)
};

(: Suche nach den Autoren und der Rollen :)
declare function search:author_build($db as node()*) as node()* {
        for $person in search:get-parameters("person")
           for $role in search:get-parameters("role")
                let $merge := concat('("person","role"),','"',$person,'","',$role,'"')
                let $build_range :=concat("//range:field-eq(",$merge,")")
                let $build_search := concat("$db",$build_range)
           return util:eval($build_search)
};

(: Suche nach Datumsbereich :)
declare function search:date_build($db as node()*) as node()* {
     let $start := if(search:get-parameters("after") ="") then xs:integer("1900") else xs:integer(search:get-parameters("after"))
     let $end := if( search:get-parameters("before") = "") then xs:integer("1935") else xs:integer(search:get-parameters("before"))
     let $paras := ("date","date_when","date_notBefore","date_notAfter","date_from","date_to")
     for $date in ($start to $end)
        for $para in $paras
         let $result := search:date_search($db,$para,$date)
         return $result
     
};

declare function search:date_search($db as node()*,$para as xs:string,$date as xs:string)as node()* {
        let $search_terms := concat('("',$para,'"),"',$date,'"')
        let $search_funk := concat("//range:field-contains(",$search_terms,")")
        let $search_build := concat("$db",$search_funk)
        return util:eval($search_build)
};

(: Profi Result :)
declare function search:profiresult($node as node(), $model as map(*), $sel as xs:string) as node()+ {
if(exists($sel) and $sel = "union") 
    then
    if(exists($model(concat("r_",$sel))))
    then if ($model("query")!="") then 
        for $hit in $model(concat("r_",$sel))
            let $file_name := root($hit)/util:document-name(.)
            let $expanded := kwic:expand($hit)
            let $title := 
            if(doc(concat("/db/apps/pessoa/data/doc/",$file_name))//tei:sourceDesc/tei:msDesc) 
                then doc(concat("/db/apps/pessoa/data/doc/",$file_name))//tei:msDesc/tei:msIdentifier/tei:idno[1]/data(.)
                else doc(concat("/db/apps/pessoa/data/pub/",$file_name))//tei:biblStruct/tei:analytic/tei:title[1]/data(.)
            order by $file_name
            return if(substring-after($file_name,"BNP") != "" or substring-after($file_name,"X"))
                    then <li><a href="{$helpers:app-root}/data/doc/{concat(substring-before($file_name, ".xml"),'?term=',$model("query"), '&amp;file=', $file_name)}">{$title}</a>
                        {kwic:get-summary($expanded,($expanded//exist:match)[1], <config width ="40"/>)}</li>
                    else <li><a href="{$helpers:app-root}/data/pub/{concat(substring-before($file_name, ".xml"),'?term=',$model("query"), '&amp;file=', $file_name)}">{$title}</a>
                        {kwic:get-summary($expanded,($expanded//exist:match)[1], <config width ="40"/>)}</li>
            
        else for $hit in $model(concat("r_",$sel))
            let $file_name := root($hit)/util:document-name(.)
            let $title := 
            if(doc(concat("/db/apps/pessoa/data/doc/",$file_name))//tei:sourceDesc/tei:msDesc) 
                then doc(concat("/db/apps/pessoa/data/doc/",$file_name))//tei:msDesc/tei:msIdentifier/tei:idno[1]/data(.)
                else doc(concat("/db/apps/pessoa/data/pub/",$file_name))//tei:biblStruct/tei:analytic/tei:title[1]/data(.)
                order by $file_name
                return if(substring-after($file_name,"BNP") != "" or substring-after($file_name,"X"))
                        then <li><a href="{$helpers:app-root}/data/doc/{concat(substring-before($file_name, ".xml"),'?term=',$model("query"), '&amp;file=', $file_name)}">{$title}</a></li>
                        else <li><a href="{$helpers:app-root}/data/pub/{concat(substring-before($file_name, ".xml"),'?term=',$model("query"), '&amp;file=', $file_name)}">{$title}</a></li>
    else <p>Nothing found</p>
    else <p>Error</p>
};

declare function search:result_union($model as node()*) as node()* {
 if (exists($model))
 then let $union := $model
  return   $union | $union
else ()
};
declare function search:highlight-matches($node as node(), $model as map(*), $term as xs:string?, $sel as xs:string, $file as xs:string?) as node() {
if($term and $file and $sel and $sel="text","head","lang") 
    then
        let $result := if ($sel = "text")
        then doc(concat("/db/apps/pessoa/data/doc/",$file))//tei:text[ft:query(.,$term)]
        else ()
        let $css := doc("/db/apps/pessoa/highlight-matches.xsl")
        let $exp := if (exists($result)) then kwic:expand($result[1]) else ()
        let $exptrans := if (exists($exp))
                         then transform:transform($exp, $css, ())
                         else ()
        return
            if (exists($exptrans))
            then $exptrans
            else $node
    else $node
};

declare function search:search-function($node as node(), $model as map(*)) as node() {
    let $func := "function search()"
        let $lang := if(request:get-parameter("plang",'')!="") then request:get-parameter("plang",'') else "pt"

    return <script> {$func} {{var value = $("#search").val();
                location.href="{$helpers:app-root}/search?term="+value+"&amp;search=simple&amp;plang={$lang}";
                }};</script>
};

declare function search:search-page($node as node(), $model as map(*)) as node()* {
    let $doc := doc('/db/apps/pessoa/data/lists.xml')
    let $filter := 
     <div class="search_filter">
                       <form class="/helpers:app-root" action="search?plang={$helpers:web-language}" method="post" id="search">
                            <!-- Nachher mit class="search:profisearch austauschen -->
            <div class="tab" id="ta_author" onclick="hide('se_author')"><h6>{page:singleAttribute($doc,"navigation","autores")}</h6>
            </div>
            <div class="selection" id="se_author">
                {page:createInput_term("search","checkbox","notional",("real","mentioned"),$doc)}
                
                <br/>
                <select name="person" size="5" multiple="multiple">
                    {search:page_createOption_authors("authors",("FP","AC","AdC","RR"),$doc)}
                </select>
                <p class="small_text">{page:singleAttribute($doc,"search","multiple_entries")}</p>
                <br/>
                {page:singleAttribute($doc,"search","mentioned_as")}
                {page:createInput_item("roles","checkbox","role",("autor","editor","tradutor","tema"),$doc)}
                </div>
                <div class="tab" id="ta_release" onclick="hide('se_release')"><h6>{page:singleAttribute($doc,"search","published")}&amp;{page:singleAttribute($doc,"search","unpublished")}</h6>
                </div>
                <div class="selection" id="se_release">
                {page:createInput_term("search","radio","release",("published","unpublished"),$doc)}
                <input type="radio" name="release" value="either" id="either" checked="checked"/>
                <label for="either">{page:singleAttribute($doc,"search","published")}&amp;{page:singleAttribute($doc,"search","unpublished")}</label>
                </div>
                <div class="tab" id="ta_genre" onclick="hide('se_genre')"><h6>{page:singleAttribute($doc,"search","genre")}</h6>
                </div>
                    <div class="selection" id="se_genre">
                        <select name="genre" size="7" multiple="multiple">
                        {page:createOption("genres",("lista_editorial","nota_editorial","plano_editorial","poesia"),$doc)}
                        </select>
                        <p class="small_text">{page:singleAttribute($doc,"search","multiple_entries")}</p>
                    </div>
                  <div class="tab" id="ta_date" onclick="hide('se_date')"><h6>{page:singleAttribute($doc,"search","date")}</h6></div>
                            <div class="selection" id="se_date">    
                                <div id="datum">
                                    <input type="date" name="after"/>
                                    <label>to</label>
                                    <input type="date" name="before"/>
                                </div>
                    </div>  
                    <div class="tab" id="ta_lang" onclick="hide('se_lang')"><h6>{page:singleAttribute($doc,"search","language")}</h6></div>
                            <div class="selection" id="se_lang">
                                {search:page_createInput_item_lang("language","checkbox","lang",("pt","en","fr"),$doc)}
                                <br/>
                                <input type="radio" name="lang_ao" value="and" id="and"/>
                                    <label for="and">and</label>
                                <input type="radio" name="lang_ao" value="or" id="or" checked="checked"/>
                                    <label for="or">or</label>
                            </div>
                     <h6>{page:singleAttribute($doc,"search","free_search")}</h6>
                     <input name="term" placeholder="{page:singleAttribute($doc,"search","search_term")}..." />
             <br/>
           <button>{page:singleAttribute($doc,"search","search_verb")}</button>
      
</form>
</div>
    return $filter
};

declare function search:page_createInput_item_lang($xmltype as xs:string,$btype as xs:string, $name as xs:string, $value as xs:string*,$doc as node()) as node()* {
    for $id in $value
        let $entry := if($helpers:web-language = "pt")
                      then $doc//tei:list[@type=$xmltype and @xml:lang=$helpers:web-language]/tei:item[@xml:id=$id]
                      else $doc//tei:list[@type=$xmltype and @xml:lang=$helpers:web-language]/tei:item[@corresp=concat("#",$id)]
        let $input := <input type="{$btype}" name="{$name}" value="{$id}" id="{$id}" checked="checked"/>
        let $label := <label for="{$id}">{$entry}</label>
        return ($input,$label)
};
declare function search:page_createOption_authors($xmltype as xs:string, $value as xs:string*, $doc as node()) as node()* {
    for $id in $value
        let $entry := $doc//tei:listPerson[@type=$xmltype]/tei:person[@xml:id=$id]/tei:persName
        return <option value="{$id}">{$entry}</option>
};