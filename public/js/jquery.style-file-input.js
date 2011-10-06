/**
 * Provides a method for styling input file types.
 * 
 * @author: Ewen Elder <ewen@jainaewen.com><glomainn@yahoo.co.uk>
 * @copyright: Copyright (c) 2011 Ewen Elder
 * 
 * Dual licensed under the MIT and GPL licenses:
 * http://www.opensource.org/licenses/mit-license.php
 * http://www.gnu.org/licenses/gpl.html
 */ 
;(function ($)
{
	'use strict';
	$.fn.styleFileInput = function (options)
	{
		options = $.extend({}, $.styleFileInput.defaults, options);
		
		return $(this).each(function (i)
		{
			var buttonElement,
				clearLinkText,
				clone,
				container,
				doc = document,
				element = $(this),
				files,
				fileElement,
				fileName,
				i,
				isLink,
				isOpera = !!window.opera,
				isIe = !!window.ActiveXObject,
				length,
				namespace = options.namespace,
				textElement;
			
			
			// The file elements need an ID.
			if (!element.attr('id'))
			{
				element.attr('id', Math.random().toString().replace('.', '-'));
			}
			
			
			element.data('styleFileInput.options', options);
			
			
			container = $(doc.createElement(options.containerTagName)).attr({
				id : namespace + '-' + element.attr('id'),
				'class' : options.containerClassName
			}).insertAfter(element);
			
			
			$(doc.createElement('span'))
				.appendTo(container)
				.append(element);
			
			
			$(doc.createElement('input'))
				.attr(options.buttonAttributes)
				.attr('type', 'button')
				.appendTo(container);
			
			
			textElement = $(doc.createElement(options.textTagName))
				.attr(options.textAttributes)
				.appendTo(container);
			
			if (options.textAttributes.text)
			{
				textElement.text(options.textAttributes.text);
			}
			
			
			if (options.addClearLink)
			{
				$(doc.createElement('a'))
					.attr('href', '#')
					.appendTo(container)
					.hide();
			}
			
			
			// Set the selected file, toggle the fake file button className.
			element.bind('change.' + namespace + ' mouseover.' + namespace + ' mouseout.' + namespace, function (event)
			{
				element = $(this);
				container = element.closest('[id]:not(:input)');
				clearLinkText = $('a', container);
				textElement = $('>:nth-child(3)', container);
				buttonElement = $('[type=button]', container);
				fileName = $('[type=file]', container).val();
				files = element[0].files;
				options = element.data('styleFileInput.options');
				
				
				// Webkit still triggers an onchange event when you open the file select dialog and DON'T select a file.
				if (event.type === 'change' && element.val().length)
				{
					clearLinkText.show();
					buttonElement.addClass(options.buttonActiveClassName);
					textElement.html('');
					
					
					if (files)
					{
						fileName = [];
						
						for (i = 0, length = files.length; i < length; ++i)
						{
							if (textElement.is('input, textarea'))
							{
								fileName.push(files[i].name ? files[i].name : files[i].fileName);
							}
							
							else
							{
								$(options.textFileListHtml.replace(/%s/g, files[i].name ? files[i].name : files[i].fileName))
									.addClass(files[i].type ? files[i].type.replace(/\//g, '-') : '')
									.appendTo(textElement);
								
								clearLinkText.text(!i ? options.clearLinkText[0] : options.clearLinkText[1]);
							}
						}
						
						
						if (fileName.length)
						{
							clearLinkText.text(fileName.length === 1 ? options.clearLinkText[0] : options.clearLinkText[1]);
							fileName = fileName.toString().replace(/,/g, ', ');
						}
					}
					
					else
					{
						if (fileName.indexOf('\\') > -1)
						{
							clearLinkText.text(options.clearLinkText[0]);
							fileName = fileName.substring(fileName.lastIndexOf('\\') + 1);
						}
					}
					
					
					try
					{
						textElement.val(fileName);
						textElement.text(fileName);
					}
					
					catch (e) { }
				}
				
				else if (event.type !== 'change')
				{
					buttonElement.toggleClass(options.buttonHoverClassName);
				}
			});
			
			
			// Reset the text element.
			$('>:nth-child(3), a', container).bind('click.' + namespace + ' change.' + namespace + ' keyup.' + namespace + ' focus.' + namespace, function (event)
			{
				element = $(this);
				container = element.closest('[id]:not(:input)');
				fileElement = $('[type=file]', container);
				textElement = $('>:nth-child(3)', container);
				buttonElement = $('[type=button]', container);
				clone = fileElement.clone(true);
				isLink = element.is('a');
				options = fileElement.data('styleFileInput.options');
				
				
				// Select all content if text element is an input.
				if (event.type === 'focus' && !isLink && element.val() !== options.textAttributes.value)
				{
					// setTimeout is for webkit.
					setTimeout(function ()
					{
						textElement.select();
					}, 1);
				}
				
				// Reset the file input.
				else if ((isLink && event.type === 'click') || (!isLink && !element.val().length))
				{
					$('a', container).hide();
					buttonElement.removeClass(options.buttonActiveClassName);
					
					// IE will throw a hissy fit if you attempt to set the text of an input element, so only set options.textAttributes.text if it's not an input.
					textElement.text(options.textAttributes.text);
					textElement.val(options.textAttributes.value);
					
					// IE and Opera will not allow you to clear the file element's value, so we must clone and replace it, but IE automatically clears the value of the clone.
					if (isOpera)
					{
						clone
							.attr('type', 'text')
							.val('')
							.attr('type', 'file');
					}
					
					
					isOpera || isIe ? clone.replaceAll(fileElement) : fileElement.val('');
					
					return isLink ? false : null;
				}
			});
		});
	};
	
	
	$.styleFileInput = {
		defaults : {
			namespace : 'stylefileinput',
			containerTagName : 'span',
			containerClassName : 'stylefileinput-container',
			addClearLink : false,
			clearLinkText : ['Remove file', 'Remove files'],
			buttonHoverClassName : 'hover',
			buttonActiveClassName : 'active',
			buttonAttributes : {
				'class' : 'stylefileinput-button',
				value : 'Browse\u2026'
			},
			textTagName : 'input',
			textAttributes : {
				'class' : 'stylefileinput-text',
				type : 'text'
			},
			textFileListHtml : '<em>%s, <em>'
		}
	}
})(jQuery);