
function GetClock() {
	d = new Date();
	nhour = d.getHours();
	nmin = d.getMinutes();
	if (nmin <= 9) { nmin = "0" + nmin; }
	document.getElementById('logo').innerHTML = nhour + ":" + nmin;
	setTimeout("GetClock()", 1000);
}

function groupBy(array, f) {
	var groups = {};
	array.forEach(function(o) {
		var group = JSON.stringify(f(o));
		groups[group] = groups[group] || [];
		groups[group].push(o);  
	});
	return Object.keys(groups).map( function( group ) {
		return groups[group]; 
	});
}


function sortBy(field, reverse, primer){
   	var key = primer ? 
       function(x) {return primer(x[field])} : 
       function(x) {return x[field]};
	reverse = !reverse ? 1 : -1;
	return function (a, b) {
		return a = key(a), b = key(b), reverse * ((a > b) - (b > a));
    } 
}




$(document).ready(function(){
	document.title = 'FHEM :: dkHOME';
	
	var url = $(location).attr('href');
	var wrapper = $('<div id="pagenav-wrapper" />');				
    var dknav = $('<div id="dknav" />');
	var list = $('table.roomBlock2');
	var navitems = [];
	var order = 0;
	var groupitems = {};
	
	list.find('td').each(function(index) {
		var a = $(this).find('a');
		var a_name = a.html();
		var a_href = a.attr('href');

		var room = a_name.split(/--/);
		if (room.length > 1) {
			if (groupitems[room[0]]) {
				var orderid = groupitems[room[0]];
			} else {
				groupitems[room[0]] = order;
				var orderid = order;
			}				
			navitems.push({order: orderid, group: room[0], room: room[1], href: a_href});
		} else {
			navitems.push({order: order, group: "none", room: room[0], href: a_href});
		}
		order +=1;					
	});

	var result = groupBy(navitems, function(item) { return [item.order]; });

	for (var i = 0, len = result.length; i < len; i++) {
		var item = result[i];
		if (item[0]["group"] == "none") {
		    var menuitem = $('<a id="navitem' + i + '" class="navitem" />').attr('href', item[0]["href"]).html(item[0]["room"]);
		    if(url.indexOf(item[0]["href"]) != -1) { menuitem.addClass('selected');	}		 	
			dknav.append(menuitem);
		} else {
			var menuitem = $('<a id="navitem' + i + '" class="navitem with_sub" />').html(item[0]["group"]);
			var submenu = $('<div id="navitem' + i + 'sub" class="subnav closed" />');
			item.sort(sortBy('room', false, function(a){return a.toUpperCase()}));
			for (var si = 0, slen = item.length; si < slen; si++) {
				var subitem = item[si];
				var submenuitem = $('<a id="navitem' + i + 'sub_item' + si + '" class="subnavitem" />').attr('href', subitem["href"]).html(subitem["room"]);				
			    if(url.indexOf(subitem["href"]) != -1) {
				    menuitem.addClass('open selected');
				    submenu.removeClass('closed').addClass('open');
				    submenuitem.addClass('selected');
				}
				submenu.append(submenuitem);											
			}
			dknav.append(menuitem);
			dknav.append(submenu);											
		}
	}
	
	wrapper.append(dknav);
	$('body').append(wrapper);
	$('#menu').remove();
	
	$('.navitem.with_sub').bind('click', function(e){
		$('.subnav.open').removeClass("open").addClass("closed");
		var selected_submenu = $( "#" + $(this).attr("id") + "sub");
		if ($(this).hasClass("open") ) {
			$(this).removeClass("open");
			selected_submenu.addClass('closed').removeClass('open');
		} else {
			$('.navitem.with_sub').removeClass('open');
			$(this).addClass("open");
			selected_submenu.removeClass('closed').addClass('open');
		}
	});
	
});			


$(document).ready(function() {
	$("#content a:contains('systemCommands')").parent('div').parent('td').parent('tr').remove();
	var footernav = $('<div id="footernav"><a href="/fhem/docs/commandref.html" target="_blank">Commandref</a> | <a href="/fhem?cmd=style%20eventMonitor">Event monitor</a></div>');
	$('#content').append(footernav);
	
	if(document.URL.indexOf("showall") != -1) {
		//don't hide anything
	} else {
		$("div.devType:contains('-hidden')").parent('td').hide();
	} 

	window.addEventListener("load",GetClock,false);

	// JQUERY VERSION:
	;( function( $, window, document, undefined )
	{
		'use strict';

		var elSelector		= '#hdr, #logo',
			elClassHidden	= 'header--hidden',
			throttleTimeout	= 50,
			$element		= $( elSelector );

		if( !$element.length ) return true;

		var $window			= $( window ),
			wHeight			= 0,
			wScrollCurrent	= 0,
			wScrollBefore	= 0,
			wScrollDiff		= 0,
			$document		= $( document ),
			dHeight			= 0,

			throttle = function( delay, fn )
			{
				var last, deferTimer;
				return function()
				{
					var context = this, args = arguments, now = +new Date;
					if( last && now < last + delay )
					{
						clearTimeout( deferTimer );
						deferTimer = setTimeout( function(){ last = now; fn.apply( context, args ); }, delay );
					}
					else
					{
						last = now;
						fn.apply( context, args );
					}
				};
			};

		$window.on( 'scroll', throttle( throttleTimeout, function()
		{			
			dHeight			= $document.height();
			wHeight			= $window.height();
			wScrollCurrent	= $window.scrollTop();
			wScrollDiff		= wScrollBefore - wScrollCurrent;

			if( wScrollCurrent <= 50 ) // scrolled to the very top; element sticks to the top
			{	
				$element.removeClass( elClassHidden );
			}
			else if( wScrollDiff > 0 && $element.hasClass( elClassHidden ) ) // scrolled up; element slides in
			{
				//$element.removeClass( elClassHidden );
			}
			else if( wScrollDiff < 0 ) // scrolled down
			{
				
				if( wScrollCurrent + wHeight >= dHeight && $element.hasClass( elClassHidden ) ) // scrolled to the very bottom; element slides in
				{
					//$element.removeClass( elClassHidden );
				}
				else // scrolled down; element slides out
				{
					$element.addClass( elClassHidden );
				}
			}

			wScrollBefore = wScrollCurrent;
		}));

	})( jQuery, window, document );
	
});