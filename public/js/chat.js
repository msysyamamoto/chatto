$(function() {
  if ($("#chat_box").length > 0) {
    $.get('/room.json', {}, function(json){
      var room = $.parseJSON(json);
      $('#room_name').text(room.name);

      var sock = new Pusher('d0d8b7b3b8fa92ca9954');

      var ch = sock.subscribe('presence-' + room.name);

      /* old version
      sock.bind('pusher:connection_established', function(evt){
        toggle_text();
        $('#text').focus();
      });
      */
      sock.connection.bind('connected', function() {
        toggle_text();
        $('#text').focus();
      });

      ch.bind('pusher:subscription_succeeded', function(member_list){
        $.each(member_list._members_map, function(i, member){
          join({id:i, info:member});
        });
      });

      ch.bind('pusher:member_added', function(member){
        join(member);
      });

      ch.bind('pusher:member_removed', function(member){
        unjoin(member);
      });

      ch.bind('chat_post', function(data) {
        you_have_got_message(data);
      });
    });

    $('#text_form').submit(function() {
      if ($('#text').val().length > 0) {
          toggle_text();

          $.ajax({
            type: 'POST',
            url:  '/post',
            data: {'text': $('#text').val(), name: $('#name').text()},
            success: function(data) {
              $('#text').val('');
            },
            error: function(data) {
              $('.messages').empty();
              $('.messages').append(
                '<ul><li>Failed to post message.</li></ul>'
              );
              $('.messages').show();
              setTimeout(function() { $('.messages').fadeOut('slow'); }, 3000);
            },
            complete: function (XMLHttpRequest, textStatus) {
              toggle_text();
              $('#text').focus();
            }
          });
      }
      return false;
    });

  }

  $('#text').corner('4px');
  $('#chat_box').corner('top 8px');
  $('#text_form').corner('bottom 8px');
  $('.messages').corner('4px');
  $('#room_name_form').corner('4px');
  $('#room_name_form').focus();
  
  setTimeout(function() { $('.messages').fadeOut('slow'); }, 3500);
});

function you_have_got_message(data) {
  $('#template_draw').setTemplateElement('chat_template');
  $('#template_draw').processTemplate(data);
  $('#texts').prepend($('#template_draw').html());
  $('.chat_item:first').fadeIn('normal'); 
}

function join(member) {
  var id = make_member_id(member);
  $('#template_draw').setTemplateElement('member_template');
  $('#template_draw').processTemplate(member);
  $('#members').append($('#template_draw').html());
  $(id).fadeIn('slow');
}

function unjoin(member) {
  var id = make_member_id(member);
  $(id).fadeOut('slow', function() {$(this).remove();});
}

function make_member_id(member) {
  return '#member-' + member.id;
}

function toggle_text() {
    var txt = $('#text');
    if (txt.is('.entext') == true) {
      txt.attr('disabled', 'disabled');
      txt.removeClass('entext');
      txt.addClass('distext');
    } else {
      txt.attr('disabled', '');
      txt.removeClass('distext');
      txt.addClass('entext');
    }
}

function mwrap(obj) {
  for (var id in obj) {
    return {user_id:id, user_info:{image_url:obj[id].image_url, login:obj[id].login, name:obj[id].name}};
  }
}
