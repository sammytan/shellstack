var strVarCity = '';
strVarCity += '<div class="aui_state_box" style="z-index: 19891016;"><div class="aui_state_box_bg"></div>';
strVarCity += '  <div class="aui_alert_zn aui_outer">';
strVarCity += '    <table class="aui_border" style="border:2px solid #fff;">';
strVarCity += '      <tbody>';
strVarCity += '        <tr>';
strVarCity += '          <td class="aui_c">';
strVarCity += '            <div class="aui_inner">';
strVarCity += '              <table class="aui_dialog">';
strVarCity += '                <tbody>';
strVarCity += '                  <tr>';
strVarCity += '                    <td class="aui_header" colspan="2"><div class="aui_titleBar">';
strVarCity += '                      <div class="aui_title" style="cursor: move;">选择地区信息</div>';
strVarCity += '                        <span class="layui-layer-setwin"><a class="layui-layer-ico layui-layer-close layui-layer-close2" href="javascript:;" onclick="Close()"></a></span>';
// strVarCity += '                        <a href="javascript:;" class="aui_close" onclick="Close()">×</a>';
strVarCity += '                      </div>';
strVarCity += '                    </td>';
strVarCity += '                  </tr>';
strVarCity += '                  <tr>';
strVarCity += '                  <tr>';
strVarCity += '                    <td class="aui_icon" style="display: none;">';
strVarCity += '                     <div class="aui_iconBg" style="background: transparent none repeat scroll 0% 0%;"></div></td>';
strVarCity += '                       <td class="aui_main" style="width: auto; height: auto;">';
strVarCity += '                        <div class="aui_content" style="padding: 0px; position:relative">';
strVarCity += '                        <div class="flex layui-layer-content selectRegionManu"><div class="aui_selectType"></div><div class="aui_selectDomain"></div></div>';
strVarCity += '                          <div id="" style="width: 680px; position:relative;">';
strVarCity += '                            <div class="data-result"><em>最多选择 <strong>2000</strong> 项</em></div>';
strVarCity += '                            <div class="data-error" style="display: none;">最多只能选择 3 项</div>';
strVarCity += '                            <div class="data-search" id="searchRun"><input class="bt-input-text" style="width:200px;" name="searcharea"/><div class="searchList run"></div></div>';
strVarCity += '                            <div class="data-tabs">';
strVarCity += '                              <ul>';
strVarCity += '                                <li onclick="removenode_area(this)" data-selector="tab-all" class="active"><a href="javascript:;"><span>全部</span><em></em></a></li>';
strVarCity += '                              </ul>';
strVarCity += '                            </div>';
strVarCity += '                            <div class="data-container data-container-city">';
strVarCity += '                            </div>';
strVarCity += '                          </div>';
strVarCity += '                        </div>';
// strVarCity += '                        <div class="aui_selectDomain"></div>';

strVarCity += '                      </div>';
strVarCity += '                    </td>';
strVarCity += '                  </tr>';
strVarCity += '                  <tr>';
strVarCity += '                    <td class="aui_footer" colspan="2">';
strVarCity += '                      <div class="aui_buttons">';
strVarCity += '                      <button class="aui-btn aui-btn-primary" onclick="svae_City()" type="button">确定</button>';
strVarCity += '                        <button class="aui-btn aui-btn-light" onclick="Close()" type="button">取消</button>';
strVarCity += '                      </div>';
strVarCity += '                    </td>';
strVarCity += '                  </tr>';
strVarCity += '                </tbody>';
strVarCity += '              </table>';
strVarCity += '            </div></td>';
strVarCity += '        </tr>';
strVarCity += '      </tbody>';
strVarCity += '    </table>';
strVarCity += '  </div>';
strVarCity += '</div>';

// 全局变量
var datatype        = "";
var dataCityinput   = null;
var searchValue     = null;
var regionSelectType          = 0;      //      0选择地区限制        1限制省市限制
var addTypeSelect=null;
var callBack=null;
// $(document).on('click', '#select-region', function () {
//     appendCity(this, 'duoxuan');
// 		if($('#select-region').data('ploy')==1){
// 			$($('#check_ploy .check')[1]).addClass('active')
// 		}else{
// 			$($('#check_ploy .check')[0]).addClass('active')
// 		}
// });

$(document).on('click', '.area-danxuan', function () {
    appendCity(this, 'danxuan');
});
// 选择策略事件绑定
$(document).on('click', '#check_ploy .check',function(){
	$(this).addClass('active').siblings().removeClass('active')
})
function appendCity(thiscon, Cityxz,selectType,callback) {
		callBack = callback
    dataCityinput = thiscon;
    datatype = Cityxz;
		regionSelectType=selectType
		searchValue  = searchdata()
    $('body').append(strVarCity);

		addTypeSelect = bt_tools.form({
			el: '.aui_selectType',
			form: [
				{
					label: '类型',
					group: {
						name: 'types',
						width: '200px',
						type: 'select',
						list: [
							{ title: '拦截', value: 'refuse' },
							{ title: '只放行', value: 'accept' },
						],
					},
				},
			],
		});

    if (datatype == "danxuan") {
        $('.data-result').find('strong').text('1');
    } else {
        $('.data-result').html('<em>地区（可选择多项）：</em>');
        // $('.data-result').html('<em>选择'+ type +'地区（可选择多项）：</em>');
				// $('.aui_title').text('选择'+ type +'地区')
				if(regionSelectType){
					$('.aui_title').text('添加国内省市限制')
				}else{
					$('.aui_title').text('添加地区限制')
				}
    }
    // if ($(dataCityinput).data("value") != "") {
    //     var inputarry = $(dataCityinput).data("value").split('-');
    //     var inputarryname = $(dataCityinput).val().split('-');
    //     if (inputarry.length > 0) {
    //         for (var i in inputarry) {
    //             $('.data-result').append('<span class="svae_box aui-titlespan" data-code="' + inputarry[i] + '" data-name="' + inputarryname[i] + '" onclick="removespan_area(this)">' + inputarryname[i] + '<i>×</i></span>');
    //         }
    //     }
    // }

    var minwid = document.documentElement.clientWidth;
    $('.aui_outer .aui_header').on("mousedown", function (e) {
        /*$(this)[0].onselectstart = function(e) { return false; }*///防止拖动窗口时，会有文字被选中的现象(事实证明不加上这段效果会更好)
        $(this)[0].oncontextmenu = function (e) { return false; } //防止右击弹出菜单
        var getStartX = e.pageX;
        var getStartY = e.pageY;
        var getPositionX = (minwid / 2) - $(this).offset().left,
            getPositionY = $(this).offset().top;
						$(document).on("mousemove.move", function (e) {
            var getEndX = e.pageX;
            var getEndY = e.pageY;
            $('.aui_outer').css({
                left: getEndX - getStartX - getPositionX + ($('.aui_outer .aui_header')[0].clientWidth / 2),
                top: getEndY - getStartY + getPositionY + ($('.aui_outer').height() / 2)
            });
        });
				$(document).on("mouseup", function () {
					$(document).off("mousemove.move");
        })
    });
    selectProvince('all', null, '');
    auto_area.run();
}

var dataarrary = __LocalDataCities.list;
function selectProvince(type, con, isremove) {
    //显示省级
    var strVarCity = "";
    if (type == "all") {
        var dataCityxz      = __LocalDataCities.category.provinces;
        var datahotcityxz   = __LocalDataCities.category.hotcities;
        var dataCountryxz   = __LocalDataCities.category.continents;
				var dataHotRegion   =__LocalDataCities.category.hotregion
        // 加载热门城市和省份
        strVarCity += '<div class="view-all" id="">';
				if(regionSelectType){    
					//选择省市限制
					strVarCity += '  <p class="data-title">热门地区</p>';
        strVarCity += '    <div class="data-list data-list-hot">';
        strVarCity += '      <ul class="clearfix">';
        for (var i in datahotcityxz) {
            strVarCity += '<li><a href="javascript:;" data-code="' + datahotcityxz[i] + '" data-name="' + dataarrary[datahotcityxz[i]][0] + '" class="d-item"  onclick="selectProvince(\'sub\',this,\'\')">' + dataarrary[datahotcityxz[i]][0] + '<label>0</label></a></li>';
        }
        strVarCity += '      </ul>';
        strVarCity += '    </div>';
        strVarCity += '    <p class="data-title">中国省份</p>';
        strVarCity += '   <div class="data-list data-list-provinces">';
        strVarCity += '  <ul class="clearfix">';
        for (var i in dataCityxz) {
            strVarCity += '<li><a href="javascript:;" data-code="' + dataCityxz[i] + '" data-name="' + dataarrary[dataCityxz[i]][0] + '" class="d-item"  onclick="selectProvince(\'sub\',this,\'\')">' + dataarrary[dataCityxz[i]][0] + '<label>0</label></a></li>';
        }
        strVarCity += ' </ul>';
        strVarCity += '</div>';
				}else{       
					 //选择地区限制
					 strVarCity += '  <p class="data-title">热门地区</p>';
        strVarCity += '    <div class="data-list data-list-hot">';
        strVarCity += '      <ul class="clearfix">';
        for (var i in dataHotRegion) {
            strVarCity += '<li><a href="javascript:;" data-code="' + dataHotRegion[i] + '" data-name="' + dataarrary[dataHotRegion[i]][0] + '" class="d-item"  onclick="selectProvince(\'sub\',this,\'\')">' + dataarrary[dataHotRegion[i]][0] + '<label>0</label></a></li>';
        }
        strVarCity += '      </ul>';
        strVarCity += '    </div>';
					strVarCity += '    <p class="data-title">其他地区</p>';
					strVarCity += '   <div class="data-list data-list-provinces">';
					strVarCity += '  <ul class="clearfix">';
					for (var i in dataCountryxz) {
							strVarCity += '<li><a href="javascript:;" data-code="' + dataCountryxz[i] + '" data-name="' + dataarrary[dataCountryxz[i]][0] + '" class="d-item"  onclick="selectProvince(\'sub\',this,\'\')">' + dataarrary[dataCountryxz[i]][0] + '<label>0</label></a></li>';
					}
					strVarCity += ' </ul>';
				}
        strVarCity += '</div>';
        $('.data-container-city').html(strVarCity);

        $('.data-result span').each(function (index) {
            if ($('a[data-code=' + $(this).data("code") + ']').length > 0) {
                $('a[data-code=' + $(this).data("code") + ']').addClass('d-item-active');
                if ($('a[data-code=' + $(this).data("code") + ']').attr("class").indexOf('data-all') > 0) {
                    $('a[data-code=' + $(this).data("code") + ']').parent('li').nextAll('li').find('a').css({ 'color': '#ccc', 'cursor': 'not-allowed' });
                    $('a[data-code=' + $(this).data("code") + ']').parent('li').nextAll("li").find('a').attr("onclick", "");
                } else {
                    if ($('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').length > 0) {
                        var numlabel = $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text();
                        $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) + 1).show();
                    }
                }
            } else {
                var numlabel = $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text();
                $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) + 1).show();
            }
        });
    }
    //显示下一级
    else {
        var dataCityxz = __LocalDataCities.category.provinces;
        var relations  = __LocalDataCities.relations;
        if (typeof (relations[$(con).data("code")]) != "undefined") {
            //添加标题
            if (isremove != "remove") {
                $('.data-tabs li').each(function () {
                    $(this).removeClass('active');
                });
                $('.data-tabs ul').append('<li data-code=' + $(con).data("code") + ' data-name=' + $(con).data("name") + ' class="active" onclick="removenode_area(this)"><a href="javascript:;"><span>' + $(con).data("name") + '</span><em></em></a></li>');
            }
            //添加内容
            strVarCity += '<ul class="clearfix">';
            if (datatype == "danxuan") {
                strVarCity += '<li class="li-disabled" style="width:100%" ><a href="javascript:;" class="d-item data-all"  data-code="' + $(con).data("code") + '"  data-name="' + $(con).data("name") + '">' + $(con).data("name") + '<label>0</label></a></li>';
            } else {
							if(regionSelectType){
                strVarCity += '<li class="d-item"><a href="javascript:;" class="d-item data-all"  data-code="' + $(con).data("code") + '"  data-name="' + $(con).data("name") + '"  onclick="selectitem_area(this)">' + $(con).data("name") + '<label>0</label></a></li>';
							}
            }
            for (var i in relations[$(con).data("code")]) {
                strVarCity += '<li><a href="javascript:;" class="d-item" data-code="' + relations[$(con).data("code")][i] + '"  data-name="' + dataarrary[relations[$(con).data("code")][i]][0] + '" onclick="selectProvince(\'sub\',this,\'\')">' + dataarrary[relations[$(con).data("code")][i]][0] + '<label>0</label></a></li>';
            }
            strVarCity += '</ul>';
            $('.data-container-city').html(strVarCity);
        } else {
            if (datatype == "duoxuan") {
                if (typeof $(con).data('flag') != 'undefined') {
                    if($('.data-result span[data-code="' + $(con).data("code") + '"]').length > 0) {
                        return false;
                    }
                }
                if ($(con).attr("class").indexOf('d-item-active') > 0) {
                    $('.data-result span[data-code="' + $(con).data("code") + '"]').remove();
                    $(con).removeClass('d-item-active');
                    // 省份显示城市数量减一,当为0时不显示
                    if ($('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').length > 0) {
                        var numlabel = $('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').find('label').text();
                        if (parseInt(numlabel) == 1) {
                            $('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').find('label').text(0).hide();
                        } else {
                            $('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) - 1);
                        }
                    }
                    return false;
                } else {
                    // 已全选省份,不可再选
                    if ($('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').hasClass('d-item-active')) {
											if(regionSelectType){
												$('.data-error').text('已全选省份,不可再选');
											}else{
												$('.data-error').text('已全选大洲,不可再选');
											}
                        $('.data-error').slideDown();
                        setTimeout("$('.data-error').text('最多只能选择 3 项').hide()", 1000);
                        return false;
                    }
                }
                if ($('.data-result span').length > 2000) {
                    $('.data-error').slideDown();
                    setTimeout("$('.data-error').hide()", 1000);
                    return false;
                } else {
                    $('.data-result').append('<span class="svae_box aui-titlespan" data-code="' + $(con).data("code") + '" data-name="' + $(con).data("name") + '" onclick="removespan_area(this)">' + $(con).data("name") + '<i>×</i></span>');
                    $(con).addClass('d-item-active');
                }
            } else {
                //单选 
                $('.data-result span').remove();
                 // 消除搜索影响
                $('.data-list-hot li').siblings('li').find('a').removeClass('d-item-active');
                $('.data-container-city li').siblings('li').find('a').removeClass('d-item-active');

                $('.data-result').append('<span class="svae_box aui-titlespan" data-code="' + $(con).data("code") + '" data-name="' + $(con).data("name") + '" onclick="removespan_area(this)">' + $(con).data("name") + '<i>×</i></span>');
                $(con).parent('li').siblings('li').find('a').removeClass('d-item-active')
                $(con).addClass('d-item-active');

                $('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').removeClass('d-item-active');
                $('.data-list-provinces a[data-code=' + $(con).data("code").toString().substring(0, 3) + ']').find('label').text(0).hide();
            }
        }
        $('.data-result span').each(function () {
            $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text(0).hide();
        });
        $('.data-result span').each(function () {
            if ($('a[data-code=' + $(this).data("code") + ']').length > 0) {
                $('a[data-code=' + $(this).data("code") + ']').addClass('d-item-active');
                if ($('a[data-code=' + $(this).data("code") + ']').attr("class").indexOf('data-all') > 0) {
                    if (datatype == "duoxuan") {
                        $('a[data-code=' + $(this).data("code") + ']').parent('li').nextAll('li').find('a').css({ 'color': '#ccc', 'cursor': 'not-allowed' });
                        $('a[data-code=' + $(this).data("code") + ']').parent('li').nextAll("li").find('a').attr("onclick", "");
                    }
                } else {
                    if (datatype == "danxuan") {
                        $('.data-list-provinces a').each(function () {
                            $(this).find('label').text(0).hide();
                        });
                    }
                    if ($('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').length > 0) {
                        var numlabel = $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text();
                        $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) + 1).show();
                    }
                }
            } else {
                var numlabel = $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text();
                $('.data-list-provinces a[data-code=' + $(this).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) + 1).show();
            }
        });
    }
}

function selectitem_area(con) {
    if (datatype == "duoxuan") {
        //多选
        if ($('.data-result span').length > 2000) {
            $('.data-error').slideDown();
            setTimeout("$('.data-error').hide()", 1000);
            return false;
        } else {
            $('.data-result span').each(function () {
                if ($(this).data("code").toString().substring(0, $(con).data("code").toString().length) == $(con).data("code").toString()) {
                    $(this).remove();
                }
            })
            $(con).parent('li').siblings('li').find("a").removeClass("d-item-active");

            if ($(con).attr("class").indexOf("d-item-active") == -1) {
                $(con).parent('li').nextAll("li").find('a').css({ 'color': '#ccc', 'cursor': 'not-allowed' })
                $(con).parent('li').nextAll("li").find('a').attr("onclick", "");
            } else {
                $(con).parent('li').nextAll("li").find('a').css({ 'color': '#666', 'a.d-item-active:hover': '#fff', 'cursor': 'pointer' })
                $(con).parent('li').nextAll("li").find('a').attr("onclick", 'selectProvince("sub",this,"")');
            }
            if ($(con).attr("class").indexOf('d-item-active') > 0) {
                $('.data-result span[data-code="' + $(con).data("code") + '"]').remove();
                $(con).removeClass('d-item-active');
                return false;
            }
            $('.data-result').append('<span class="svae_box aui-titlespan" data-code="' + $(con).data("code") + '" data-name="' + $(con).data("name") + '" onclick="removespan_area(this)">' + $(con).data("name") + '<i>×</i></span>');
            $(con).addClass('d-item-active');
        }
    } else {
        //单选
        $('.data-result span').remove();
        $('.data-result').append('<span class="svae_box aui-titlespan" data-code="' + $(con).data("code") + '" data-name="' + $(con).data("name") + '" onclick="removespan_area(this)">' + $(con).data("name") + '<i>×</i></span>');
        $(con).parent('li').siblings('li').find('a').removeClass('d-item-active')
        $(con).addClass('d-item-active');
    }
}

function removenode_area(lithis) {
    $(lithis).siblings().removeClass('active');
    $(lithis).addClass('active');
    if ($(lithis).nextAll('li').length == 0) {
        return false;
    }
    $(lithis).nextAll('li').remove();
    if ($(lithis).data("selector") == "tab-all") {
        selectProvince('all', null, '');
    } else {
        selectProvince('sub', lithis, 'remove');
    }
}

function removespan_area(spanthis) {
    $('a[data-code=' + $(spanthis).data("code") + ']').removeClass('d-item-active');
    if ($('a[data-code=' + $(spanthis).data("code") + ']').length > 0) {
        if ($('a[data-code=' + $(spanthis).data("code") + ']').attr("class").indexOf('data-all') > 0) {
            $('a[data-code=' + $(spanthis).data("code") + ']').parent('li').nextAll('li').find('a').css({ 'color': '#666', 'a.d-item-active:hover': '#fff', 'cursor': 'pointer' });
            $('a[data-code=' + $(spanthis).data("code") + ']').parent('li').nextAll("li").find('a').attr("onclick", 'selectProvince("sub",this,"")');
        }
    }
    if ($('.data-list-provinces a[data-code=' + $(spanthis).data("code").toString().substring(0, 3) + ']').length > 0) {
        var numlabel = $('.data-list-provinces a[data-code=' + $(spanthis).data("code").toString().substring(0, 3) + ']').find('label').text();
        if (parseInt(numlabel) == 1) {
            $('.data-list-provinces a[data-code=' + $(spanthis).data("code").toString().substring(0, 3) + ']').find('label').text(0).hide();
        } else {
            $('.data-list-provinces a[data-code=' + $(spanthis).data("code").toString().substring(0, 3) + ']').find('label').text(parseInt(numlabel) - 1);
        }
    }
    $(spanthis).remove();
}

//确定选择
function svae_City() {
    var val = '';
    var Cityname = '';
    if ($('.svae_box').length > 0) {
        $('.svae_box').each(function () {
            val += $(this).data("code") + '-';
            Cityname += $(this).data("name") + ',';
        });
    }
    if (val != '') {
        val = val.substring(0, val.lastIndexOf('-'));
    }
    if (Cityname != '') {
        Cityname = Cityname.substring(0, Cityname.lastIndexOf(','));
    }

    $(dataCityinput).data("value", val);
    $(dataCityinput).data("ploy", $('#check_ploy .active').data('ploy'));
    $(dataCityinput).val(Cityname);
		$('.area-duoxuan').data("value", val);
    $('.area-duoxuan').val(Cityname);
		if(callBack) callBack(addTypeSelect,Cityname,Close)
    // Close();
		$('.area-duoxuan').trigger('input')
}

function Close() {
    $('.aui_state_box').remove();
}

function searchdata() {
    var list    = __LocalDataCities.list;
    var dataArr = [];
    for (var i in list) {
			if(regionSelectType){
				// 选择省市限制
				if (i.length > 6 || String(i).slice(0,3) >= 350) {
					continue;
			}
			}else{
				// 选择地区限制
				if (i.length > 6 || String(i).slice(0,3) < 350 || String(i).slice(0,3) > 400) {
					continue;
			}
			}
        // if (i.length == 3 && i != '010' && i != '020' && i != '030' && i != '040') {
        //     continue;
        // }
        if (i.length > 6 || i == 'hwgat') {
            continue;
        }
        // if (parseInt(i.toString().substring(0, 2)) >= 32) {
        //     continue;
        // }
        var temp = {};
        temp.code   = i;
        temp.name   = list[i][0];
        temp.pinyin = list[i][1];
        temp.py     = list[i][2];
        dataArr.push(temp);
    }
    return dataArr;
}