var Zepto = function() {
    function a(a) {
        return null == a ? String(a) : W[X.call(a)] || "object"
    }

    function b(b) {
        return "function" == a(b)
    }

    function c(a) {
        return null != a && a == a.window
    }

    function d(a) {
        return null != a && a.nodeType == a.DOCUMENT_NODE
    }

    function e(b) {
        return "object" == a(b)
    }

    function f(a) {
        return e(a) && !c(a) && a.__proto__ == Object.prototype
    }

    function g(a) {
        return a instanceof Array
    }

    function h(a) {
        return "number" == typeof a.length
    }

    function i(a) {
        return E.call(a, function(a) {
            return null != a
        })
    }

    function j(a) {
        return a.length > 0 ? y.fn.concat.apply([], a) : a
    }

    function k(a) {
        return a.replace(/::/g, "/").replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(/([a-z\d])([A-Z])/g, "$1_$2").replace(/_/g, "-").toLowerCase()
    }

    function l(a) {
        return a in H ? H[a] : H[a] = new RegExp("(^|\\s)" + a + "(\\s|$)")
    }

    function m(a, b) {
        return "number" != typeof b || J[k(a)] ? b : b + "px"
    }

    function n(a) {
        var b, c;
        return G[a] || (b = F.createElement(a), F.body.appendChild(b), c = I(b, "").getPropertyValue("display"), b.parentNode.removeChild(b), "none" == c && (c = "block"), G[a] = c), G[a]
    }

    function o(a) {
        return "children" in a ? D.call(a.children) : y.map(a.childNodes, function(a) {
            return 1 == a.nodeType ? a : void 0
        })
    }

    function p(a, b, c) {
        for (x in b) c && (f(b[x]) || g(b[x])) ? (f(b[x]) && !f(a[x]) && (a[x] = {}), g(b[x]) && !g(a[x]) && (a[x] = []), p(a[x], b[x], c)) : b[x] !== w && (a[x] = b[x])
    }

    function q(a, b) {
        return null == b ? y(a) : y(a).filter(b)
    }

    function r(a, c, d, e) {
        return b(c) ? c.call(a, d, e) : c
    }

    function s(a, b, c) {
        null == c ? a.removeAttribute(b) : a.setAttribute(b, c)
    }

    function t(a, b) {
        var c = a.className,
            d = c && c.baseVal !== w;
        return b === w ? d ? c.baseVal : c : void(d ? c.baseVal = b : a.className = b)
    }

    function u(a) {
        var b;
        try {
            return a ? "true" == a || ("false" == a ? !1 : "null" == a ? null : isNaN(b = Number(a)) ? /^[\[\{]/.test(a) ? y.parseJSON(a) : a : b) : a
        } catch (c) {
            return a
        }
    }

    function v(a, b) {
        b(a);
        for (var c in a.childNodes) v(a.childNodes[c], b)
    }
    var w, x, y, z, A, B, C = [],
        D = C.slice,
        E = C.filter,
        F = window.document,
        G = {},
        H = {},
        I = F.defaultView.getComputedStyle,
        J = {
            "column-count": 1,
            columns: 1,
            "font-weight": 1,
            "line-height": 1,
            opacity: 1,
            "z-index": 1,
            zoom: 1
        },
        K = /^\s*<(\w+|!)[^>]*>/,
        L = /<(?!area|br|col|embed|hr|img|input|link|meta|param)(([\w:]+)[^>]*)\/>/gi,
        M = /^(?:body|html)$/i,
        N = ["val", "css", "html", "text", "data", "width", "height", "offset"],
        O = ["after", "prepend", "before", "append"],
        P = F.createElement("table"),
        Q = F.createElement("tr"),
        R = {
            tr: F.createElement("tbody"),
            tbody: P,
            thead: P,
            tfoot: P,
            td: Q,
            th: Q,
            "*": F.createElement("div")
        },
        S = /complete|loaded|interactive/,
        T = /^\.([\w-]+)$/,
        U = /^#([\w-]*)$/,
        V = /^[\w-]+$/,
        W = {},
        X = W.toString,
        Y = {},
        Z = F.createElement("div");
    return Y.matches = function(a, b) {
        if (!a || 1 !== a.nodeType) return !1;
        var c = a.webkitMatchesSelector || a.mozMatchesSelector || a.oMatchesSelector || a.matchesSelector;
        if (c) return c.call(a, b);
        var d, e = a.parentNode,
            f = !e;
        return f && (e = Z).appendChild(a), d = ~Y.qsa(e, b).indexOf(a), f && Z.removeChild(a), d
    }, A = function(a) {
        return a.replace(/-+(.)?/g, function(a, b) {
            return b ? b.toUpperCase() : ""
        })
    }, B = function(a) {
        return E.call(a, function(b, c) {
            return a.indexOf(b) == c
        })
    }, Y.fragment = function(a, b, c) {
        a.replace && (a = a.replace(L, "<$1></$2>")), b === w && (b = K.test(a) && RegExp.$1), b in R || (b = "*");
        var d, e, g = R[b];
        return g.innerHTML = "" + a, e = y.each(D.call(g.childNodes), function() {
            g.removeChild(this)
        }), f(c) && (d = y(e), y.each(c, function(a, b) {
            N.indexOf(a) > -1 ? d[a](b) : d.attr(a, b)
        })), e
    }, Y.Z = function(a, b) {
        return a = a || [], a.__proto__ = y.fn, a.selector = b || "", a
    }, Y.isZ = function(a) {
        return a instanceof Y.Z
    }, Y.init = function(a, c) {
        if (a) {
            if (b(a)) return y(F).ready(a);
            if (Y.isZ(a)) return a;
            var d;
            if (g(a)) d = i(a);
            else if (e(a)) d = [f(a) ? y.extend({}, a) : a], a = null;
            else if (K.test(a)) d = Y.fragment(a.trim(), RegExp.$1, c), a = null;
            else {
                if (c !== w) return y(c).find(a);
                d = Y.qsa(F, a)
            }
            return Y.Z(d, a)
        }
        return Y.Z()
    }, y = function(a, b) {
        return Y.init(a, b)
    }, y.extend = function(a) {
        var b, c = D.call(arguments, 1);
        return "boolean" == typeof a && (b = a, a = c.shift()), c.forEach(function(c) {
            p(a, c, b)
        }), a
    }, Y.qsa = function(a, b) {
        var c;
        return d(a) && U.test(b) ? (c = a.getElementById(RegExp.$1)) ? [c] : [] : 1 !== a.nodeType && 9 !== a.nodeType ? [] : D.call(T.test(b) ? a.getElementsByClassName(RegExp.$1) : V.test(b) ? a.getElementsByTagName(b) : a.querySelectorAll(b))
    }, y.contains = function(a, b) {
        return a !== b && a.contains(b)
    }, y.type = a, y.isFunction = b, y.isWindow = c, y.isArray = g, y.isPlainObject = f, y.isEmptyObject = function(a) {
        var b;
        for (b in a) return !1;
        return !0
    }, y.inArray = function(a, b, c) {
        return C.indexOf.call(b, a, c)
    }, y.camelCase = A, y.trim = function(a) {
        return null == a ? "" : String.prototype.trim.call(a)
    }, y.uuid = 0, y.support = {}, y.expr = {}, y.map = function(a, b) {
        var c, d, e, f = [];
        if (h(a))
            for (d = 0; d < a.length; d++) c = b(a[d], d), null != c && f.push(c);
        else
            for (e in a) c = b(a[e], e), null != c && f.push(c);
        return j(f)
    }, y.each = function(a, b) {
        var c, d;
        if (h(a)) {
            for (c = 0; c < a.length; c++)
                if (b.call(a[c], c, a[c]) === !1) return a
        } else
            for (d in a)
                if (b.call(a[d], d, a[d]) === !1) return a;
        return a
    }, y.grep = function(a, b) {
        return E.call(a, b)
    }, window.JSON && (y.parseJSON = JSON.parse), y.each("Boolean Number String Function Array Date RegExp Object Error".split(" "), function(a, b) {
        W["[object " + b + "]"] = b.toLowerCase()
    }), y.fn = {
        forEach: C.forEach,
        reduce: C.reduce,
        push: C.push,
        sort: C.sort,
        indexOf: C.indexOf,
        concat: C.concat,
        map: function(a) {
            return y(y.map(this, function(b, c) {
                return a.call(b, c, b)
            }))
        },
        slice: function() {
            return y(D.apply(this, arguments))
        },
        ready: function(a) {
            return S.test(F.readyState) ? a(y) : F.addEventListener("DOMContentLoaded", function() {
                a(y)
            }, !1), this
        },
        get: function(a) {
            return a === w ? D.call(this) : this[a >= 0 ? a : a + this.length]
        },
        toArray: function() {
            return this.get()
        },
        size: function() {
            return this.length
        },
        remove: function() {
            return this.each(function() {
                null != this.parentNode && this.parentNode.removeChild(this)
            })
        },
        each: function(a) {
            return C.every.call(this, function(b, c) {
                return a.call(b, c, b) !== !1
            }), this
        },
        filter: function(a) {
            return b(a) ? this.not(this.not(a)) : y(E.call(this, function(b) {
                return Y.matches(b, a)
            }))
        },
        add: function(a, b) {
            return y(B(this.concat(y(a, b))))
        },
        is: function(a) {
            return this.length > 0 && Y.matches(this[0], a)
        },
        not: function(a) {
            var c = [];
            if (b(a) && a.call !== w) this.each(function(b) {
                a.call(this, b) || c.push(this)
            });
            else {
                var d = "string" == typeof a ? this.filter(a) : h(a) && b(a.item) ? D.call(a) : y(a);
                this.forEach(function(a) {
                    d.indexOf(a) < 0 && c.push(a)
                })
            }
            return y(c)
        },
        has: function(a) {
            return this.filter(function() {
                return e(a) ? y.contains(this, a) : y(this).find(a).size()
            })
        },
        eq: function(a) {
            return -1 === a ? this.slice(a) : this.slice(a, +a + 1)
        },
        first: function() {
            var a = this[0];
            return a && !e(a) ? a : y(a)
        },
        last: function() {
            var a = this[this.length - 1];
            return a && !e(a) ? a : y(a)
        },
        find: function(a) {
            var b, c = this;
            return b = "object" == typeof a ? y(a).filter(function() {
                var a = this;
                return C.some.call(c, function(b) {
                    return y.contains(b, a)
                })
            }) : 1 == this.length ? y(Y.qsa(this[0], a)) : this.map(function() {
                return Y.qsa(this, a)
            })
        },
        closest: function(a, b) {
            var c = this[0],
                e = !1;
            for ("object" == typeof a && (e = y(a)); c && !(e ? e.indexOf(c) >= 0 : Y.matches(c, a));) c = c !== b && !d(c) && c.parentNode;
            return y(c)
        },
        parents: function(a) {
            for (var b = [], c = this; c.length > 0;) c = y.map(c, function(a) {
                return (a = a.parentNode) && !d(a) && b.indexOf(a) < 0 ? (b.push(a), a) : void 0
            });
            return q(b, a)
        },
        parent: function(a) {
            return q(B(this.pluck("parentNode")), a)
        },
        children: function(a) {
            return q(this.map(function() {
                return o(this)
            }), a)
        },
        contents: function() {
            return this.map(function() {
                return D.call(this.childNodes)
            })
        },
        siblings: function(a) {
            return q(this.map(function(a, b) {
                return E.call(o(b.parentNode), function(a) {
                    return a !== b
                })
            }), a)
        },
        empty: function() {
            return this.each(function() {
                this.innerHTML = ""
            })
        },
        pluck: function(a) {
            return y.map(this, function(b) {
                return b[a]
            })
        },
        show: function() {
            return this.each(function() {
                "none" == this.style.display && (this.style.display = null), "none" == I(this, "").getPropertyValue("display") && (this.style.display = n(this.nodeName))
            })
        },
        replaceWith: function(a) {
            return this.before(a).remove()
        },
        wrap: function(a) {
            var c = b(a);
            if (this[0] && !c) var d = y(a).get(0),
                e = d.parentNode || this.length > 1;
            return this.each(function(b) {
                y(this).wrapAll(c ? a.call(this, b) : e ? d.cloneNode(!0) : d)
            })
        },
        wrapAll: function(a) {
            if (this[0]) {
                y(this[0]).before(a = y(a));
                for (var b;
                    (b = a.children()).length;) a = b.first();
                y(a).append(this)
            }
            return this
        },
        wrapInner: function(a) {
            var c = b(a);
            return this.each(function(b) {
                var d = y(this),
                    e = d.contents(),
                    f = c ? a.call(this, b) : a;
                e.length ? e.wrapAll(f) : d.append(f)
            })
        },
        unwrap: function() {
            return this.parent().each(function() {
                y(this).replaceWith(y(this).children())
            }), this
        },
        clone: function() {
            return this.map(function() {
                return this.cloneNode(!0)
            })
        },
        hide: function() {
            return this.css("display", "none")
        },
        toggle: function(a) {
            return this.each(function() {
                var b = y(this);
                (a === w ? "none" == b.css("display") : a) ? b.show(): b.hide()
            })
        },
        prev: function(a) {
            return y(this.pluck("previousElementSibling")).filter(a || "*")
        },
        next: function(a) {
            return y(this.pluck("nextElementSibling")).filter(a || "*")
        },
        html: function(a) {
            return a === w ? this.length > 0 ? this[0].innerHTML : null : this.each(function(b) {
                var c = this.innerHTML;
                y(this).empty().append(r(this, a, b, c))
            })
        },
        text: function(a) {
            return a === w ? this.length > 0 ? this[0].textContent : null : this.each(function() {
                this.textContent = a
            })
        },
        attr: function(a, b) {
            var c;
            return "string" == typeof a && b === w ? 0 == this.length || 1 !== this[0].nodeType ? w : "value" == a && "INPUT" == this[0].nodeName ? this.val() : !(c = this[0].getAttribute(a)) && a in this[0] ? this[0][a] : c : this.each(function(c) {
                if (1 === this.nodeType)
                    if (e(a))
                        for (x in a) s(this, x, a[x]);
                    else s(this, a, r(this, b, c, this.getAttribute(a)))
            })
        },
        removeAttr: function(a) {
            return this.each(function() {
                1 === this.nodeType && s(this, a)
            })
        },
        prop: function(a, b) {
            return b === w ? this[0] && this[0][a] : this.each(function(c) {
                this[a] = r(this, b, c, this[a])
            })
        },
        data: function(a, b) {
            var c = this.attr("data-" + k(a), b);
            return null !== c ? u(c) : w
        },
        val: function(a) {
            return a === w ? this[0] && (this[0].multiple ? y(this[0]).find("option").filter(function(a) {
                return this.selected
            }).pluck("value") : this[0].value) : this.each(function(b) {
                this.value = r(this, a, b, this.value)
            })
        },
        offset: function(a) {
            if (a) return this.each(function(b) {
                var c = y(this),
                    d = r(this, a, b, c.offset()),
                    e = c.offsetParent().offset(),
                    f = {
                        top: d.top - e.top,
                        left: d.left - e.left
                    };
                "static" == c.css("position") && (f.position = "relative"), c.css(f)
            });
            if (0 == this.length) return null;
            var b = this[0].getBoundingClientRect();
            return {
                left: b.left + window.pageXOffset,
                top: b.top + window.pageYOffset,
                width: Math.round(b.width),
                height: Math.round(b.height)
            }
        },
        css: function(b, c) {
            if (arguments.length < 2 && "string" == typeof b) return this[0] && (this[0].style[A(b)] || I(this[0], "").getPropertyValue(b));
            var d = "";
            if ("string" == a(b)) c || 0 === c ? d = k(b) + ":" + m(b, c) : this.each(function() {
                this.style.removeProperty(k(b))
            });
            else
                for (x in b) b[x] || 0 === b[x] ? d += k(x) + ":" + m(x, b[x]) + ";" : this.each(function() {
                    this.style.removeProperty(k(x))
                });
            return this.each(function() {
                this.style.cssText += ";" + d
            })
        },
        index: function(a) {
            return a ? this.indexOf(y(a)[0]) : this.parent().children().indexOf(this[0])
        },
        hasClass: function(a) {
            return C.some.call(this, function(a) {
                return this.test(t(a))
            }, l(a))
        },
        addClass: function(a) {
            return this.each(function(b) {
                z = [];
                var c = t(this),
                    d = r(this, a, b, c);
                d.split(/\s+/g).forEach(function(a) {
                    y(this).hasClass(a) || z.push(a)
                }, this), z.length && t(this, c + (c ? " " : "") + z.join(" "))
            })
        },
        removeClass: function(a) {
            return this.each(function(b) {
                return a === w ? t(this, "") : (z = t(this), r(this, a, b, z).split(/\s+/g).forEach(function(a) {
                    z = z.replace(l(a), " ")
                }), void t(this, z.trim()))
            })
        },
        toggleClass: function(a, b) {
            return this.each(function(c) {
                var d = y(this),
                    e = r(this, a, c, t(this));
                e.split(/\s+/g).forEach(function(a) {
                    (b === w ? !d.hasClass(a) : b) ? d.addClass(a): d.removeClass(a)
                })
            })
        },
        scrollTop: function() {
            return this.length ? "scrollTop" in this[0] ? this[0].scrollTop : this[0].scrollY : void 0
        },
        position: function() {
            if (this.length) {
                var a = this[0],
                    b = this.offsetParent(),
                    c = this.offset(),
                    d = M.test(b[0].nodeName) ? {
                        top: 0,
                        left: 0
                    } : b.offset();
                return c.top -= parseFloat(y(a).css("margin-top")) || 0, c.left -= parseFloat(y(a).css("margin-left")) || 0, d.top += parseFloat(y(b[0]).css("border-top-width")) || 0, d.left += parseFloat(y(b[0]).css("border-left-width")) || 0, {
                    top: c.top - d.top,
                    left: c.left - d.left
                }
            }
        },
        offsetParent: function() {
            return this.map(function() {
                for (var a = this.offsetParent || F.body; a && !M.test(a.nodeName) && "static" == y(a).css("position");) a = a.offsetParent;
                return a
            })
        }
    }, y.fn.detach = y.fn.remove, ["width", "height"].forEach(function(a) {
        y.fn[a] = function(b) {
            var e, f = this[0],
                g = a.replace(/./, function(a) {
                    return a[0].toUpperCase()
                });
            return b === w ? c(f) ? f["inner" + g] : d(f) ? f.documentElement["offset" + g] : (e = this.offset()) && e[a] : this.each(function(c) {
                f = y(this), f.css(a, r(this, b, c, f[a]()))
            })
        }
    }), O.forEach(function(b, c) {
        var d = c % 2;
        y.fn[b] = function() {
            var b, e, f = y.map(arguments, function(c) {
                    return b = a(c), "object" == b || "array" == b || null == c ? c : Y.fragment(c)
                }),
                g = this.length > 1;
            return f.length < 1 ? this : this.each(function(a, b) {
                e = d ? b : b.parentNode, b = 0 == c ? b.nextSibling : 1 == c ? b.firstChild : 2 == c ? b : null, f.forEach(function(a) {
                    if (g) a = a.cloneNode(!0);
                    else if (!e) return y(a).remove();
                    v(e.insertBefore(a, b), function(a) {
                        null == a.nodeName || "SCRIPT" !== a.nodeName.toUpperCase() || a.type && "text/javascript" !== a.type || a.src || window.eval.call(window, a.innerHTML)
                    })
                })
            })
        }, y.fn[d ? b + "To" : "insert" + (c ? "Before" : "After")] = function(a) {
            return y(a)[b](this), this
        }
    }), Y.Z.prototype = y.fn, Y.uniq = B, Y.deserializeValue = u, y.zepto = Y, y
}();
window.Zepto = Zepto, "$" in window || (window.$ = Zepto),
    function(a) {
        function b(a) {
            return a._zid || (a._zid = n++)
        }

        function c(a, c, f, g) {
            if (c = d(c), c.ns) var h = e(c.ns);
            return (m[b(a)] || []).filter(function(a) {
                return !(!a || c.e && a.e != c.e || c.ns && !h.test(a.ns) || f && b(a.fn) !== b(f) || g && a.sel != g)
            })
        }

        function d(a) {
            var b = ("" + a).split(".");
            return {
                e: b[0],
                ns: b.slice(1).sort().join(" ")
            }
        }

        function e(a) {
            return new RegExp("(?:^| )" + a.replace(" ", " .* ?") + "(?: |$)")
        }

        function f(b, c, d) {
            "string" != a.type(b) ? a.each(b, d) : b.split(/\s/).forEach(function(a) {
                d(a, c)
            })
        }

        function g(a, b) {
            return a.del && ("focus" == a.e || "blur" == a.e) || !!b
        }

        function h(a) {
            return p[a] || a
        }

        function i(c, e, i, j, k, l) {
            var n = b(c),
                o = m[n] || (m[n] = []);
            f(e, i, function(b, e) {
                var f = d(b);
                f.fn = e, f.sel = j, f.e in p && (e = function(b) {
                    var c = b.relatedTarget;
                    return !c || c !== this && !a.contains(this, c) ? f.fn.apply(this, arguments) : void 0
                }), f.del = k && k(e, b);
                var i = f.del || e;
                f.proxy = function(a) {
                    var b = i.apply(c, [a].concat(a.data));
                    return b === !1 && (a.preventDefault(), a.stopPropagation()), b
                }, f.i = o.length, o.push(f), c.addEventListener(h(f.e), f.proxy, g(f, l))
            })
        }

        function j(a, d, e, i, j) {
            var k = b(a);
            f(d || "", e, function(b, d) {
                c(a, b, d, i).forEach(function(b) {
                    delete m[k][b.i], a.removeEventListener(h(b.e), b.proxy, g(b, j))
                })
            })
        }

        function k(b) {
            var c, d = {
                originalEvent: b
            };
            for (c in b) s.test(c) || void 0 === b[c] || (d[c] = b[c]);
            return a.each(t, function(a, c) {
                d[a] = function() {
                    return this[c] = q, b[a].apply(b, arguments)
                }, d[c] = r
            }), d
        }

        function l(a) {
            if (!("defaultPrevented" in a)) {
                a.defaultPrevented = !1;
                var b = a.preventDefault;
                a.preventDefault = function() {
                    this.defaultPrevented = !0, b.call(this)
                }
            }
        }
        var m = (a.zepto.qsa, {}),
            n = 1,
            o = {},
            p = {
                mouseenter: "mouseover",
                mouseleave: "mouseout"
            };
        o.click = o.mousedown = o.mouseup = o.mousemove = "MouseEvents", a.event = {
            add: i,
            remove: j
        }, a.proxy = function(c, d) {
            if (a.isFunction(c)) {
                var e = function() {
                    return c.apply(d, arguments)
                };
                return e._zid = b(c), e
            }
            if ("string" == typeof d) return a.proxy(c[d], c);
            throw new TypeError("expected function")
        }, a.fn.bind = function(a, b) {
            return this.each(function() {
                i(this, a, b)
            })
        }, a.fn.unbind = function(a, b) {
            return this.each(function() {
                j(this, a, b)
            })
        }, a.fn.one = function(a, b) {
            return this.each(function(c, d) {
                i(this, a, b, null, function(a, b) {
                    return function() {
                        var c = a.apply(d, arguments);
                        return j(d, b, a), c
                    }
                })
            })
        };
        var q = function() {
                return !0
            },
            r = function() {
                return !1
            },
            s = /^([A-Z]|layer[XY]$)/,
            t = {
                preventDefault: "isDefaultPrevented",
                stopImmediatePropagation: "isImmediatePropagationStopped",
                stopPropagation: "isPropagationStopped"
            };
        a.fn.delegate = function(b, c, d) {
            return this.each(function(e, f) {
                i(f, c, d, b, function(c) {
                    return function(d) {
                        var e, g = a(d.target).closest(b, f).get(0);
                        return g ? (e = a.extend(k(d), {
                            currentTarget: g,
                            liveFired: f
                        }), c.apply(g, [e].concat([].slice.call(arguments, 1)))) : void 0
                    }
                })
            })
        }, a.fn.undelegate = function(a, b, c) {
            return this.each(function() {
                j(this, b, c, a)
            })
        }, a.fn.live = function(b, c) {
            return a(document.body).delegate(this.selector, b, c), this
        }, a.fn.die = function(b, c) {
            return a(document.body).undelegate(this.selector, b, c), this
        }, a.fn.on = function(b, c, d) {
            return !c || a.isFunction(c) ? this.bind(b, c || d) : this.delegate(c, b, d)
        }, a.fn.off = function(b, c, d) {
            return !c || a.isFunction(c) ? this.unbind(b, c || d) : this.undelegate(c, b, d)
        }, a.fn.trigger = function(b, c) {
            return ("string" == typeof b || a.isPlainObject(b)) && (b = a.Event(b)), l(b), b.data = c, this.each(function() {
                "dispatchEvent" in this && this.dispatchEvent(b)
            })
        }, a.fn.triggerHandler = function(b, d) {
            var e, f;
            return this.each(function(g, h) {
                e = k("string" == typeof b ? a.Event(b) : b), e.data = d, e.target = h, a.each(c(h, b.type || b), function(a, b) {
                    return f = b.proxy(e), e.isImmediatePropagationStopped() ? !1 : void 0
                })
            }), f
        }, "focusin focusout load resize scroll unload click dblclick mousedown mouseup mousemove mouseover mouseout mouseenter mouseleave change select keydown keypress keyup error".split(" ").forEach(function(b) {
            a.fn[b] = function(a) {
                return a ? this.bind(b, a) : this.trigger(b)
            }
        }), ["focus", "blur"].forEach(function(b) {
            a.fn[b] = function(a) {
                return a ? this.bind(b, a) : this.each(function() {
                    try {
                        this[b]()
                    } catch (a) {}
                }), this
            }
        }), a.Event = function(a, b) {
            "string" != typeof a && (b = a, a = b.type);
            var c = document.createEvent(o[a] || "Events"),
                d = !0;
            if (b)
                for (var e in b) "bubbles" == e ? d = !!b[e] : c[e] = b[e];
            return c.initEvent(a, d, !0, null, null, null, null, null, null, null, null, null, null, null, null), c.isDefaultPrevented = function() {
                return this.defaultPrevented
            }, c
        }
    }(Zepto),
    function() {
        EventEmitter = function() {}, EventEmitter.prototype.on = function(a, b) {
            this._events = this._events || {}, this._events[a] = this._events[a] || [], this._events[a].push(b)
        }, EventEmitter.prototype.off = function(a, b) {
            this.hasOwnProperty("_events") && a in this._events != !1 && this._events[a].splice(this._events[a].indexOf(b), 1)
        }, EventEmitter.prototype.emit = function(a) {
            if (this.hasOwnProperty("_events") && a in this._events != !1)
                for (var b = 0, c = this._events[a].length; c > b; b++) this._events[a][b].apply(this, Array.prototype.slice.call(arguments, 1))
        }, FileList.prototype.forEach = Array.prototype.forEach, FileList.prototype.every = Array.prototype.every, FileList.prototype.some = Array.prototype.some, FileList.prototype.filter = Array.prototype.filter, FileList.prototype.map = Array.prototype.map, FileList.prototype.reduce = Array.prototype.reduce, FileList.prototype.reduceRight = Array.prototype.reduceRight, Object.defineProperty(FileList.prototype, "size", {
            get: function() {
                return this.reduce(function(a, b) {
                    return a + b.size
                }, 0)
            }
        });
        var a = {
            get: function() {
                var a = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"],
                    b = Math.floor(Math.log(this.size) / Math.log(1024));
                return (this.size / Math.pow(1024, b)).toFixed(2) + " " + a[b]
            }
        };
        Object.defineProperty(FileList.prototype, "humanSize", a), Object.defineProperty(File.prototype, "humanSize", a);
        var b = {
            get: function() {
                return this.uploadedSize / this.size
            }
        };
        Object.defineProperty(FileList.prototype, "percentUploaded", b), Object.defineProperty(File.prototype, "percentUploaded", b), Object.defineProperty(FileList.prototype, "uploadedSize", {
            get: function() {
                return this.reduce(function(a, b) {
                    return a + (b.uploadedSize || 0)
                }, 0)
            }
        }), Object.defineProperty(File.prototype, "url", {
            get: function() {
                return window.URL.createObjectURL(this)
            }
        }), File.revokeURL = function(a) {
            window.URL.revokeObjectURL(a)
        };
        var c = function e(a, b) {
                var c = a;
                for (var d in b) "object" == typeof b[d] ? c[d] = e(a[d], b[d]) : c[d] = b[d];
                return c
            },
            d = function(a, b, d) {
                this.url = a, this.files = b, d = d || {}, this.opts = c({
                    field: "files[]",
                    method: "POST",
                    data:  "object" == typeof d ? d : {}
                }, d)
            };
        d.prototype = Object.create(EventEmitter.prototype), d.prototype.upload = function(a) {
            a && this.on("uploadcomplete", a);
            var b = this.opts,
                c = this.files,
                d = this,
                e = new FormData;
               
            c.forEach(function(a) {
                e.append(b.field, a)
            });
            Object.keys(b.data).forEach(function (key) {
				e.append(key, b.data[key]);
			});
            var f = new XMLHttpRequest;
            f.open(b.method, this.url, !0), 
            f.setRequestHeader('X-Requested-With', 'XMLHttpRequest'),
            f.upload.addEventListener("loadstart", function(a) {
                for (var b = 0, d = c.length; d > b; b++) c[b].uploadedSize = 0
            }), f.upload.addEventListener("progress", function(a) {
                if (a.lengthComputable) {
                    size = a.loaded;
                    for (var b = 0, e = c.length; e > b; b++) c[b].uploadedSize = Math.min(size, c[b].size), size -= c[b].uploadedSize, size <= 0 && (c.current = c[b], size = 0)
                }
                d.emit("uploadprogress", a, c)
            }, !1), f.upload.addEventListener("loadstart", function(a) {
                d.emit("uploadstart", a)
            }), f.upload.addEventListener("load", function(a) {
                d.emit("uploadcomplete", a)
            }), f.addEventListener("progress", function(a) {
                d.emit("progress", a)
            }), f.addEventListener("load", function(a) {
                d.emit("load", a, f.responseText)
            }), f.send(e)
        }, FileList.prototype.upload = function(a, b) {
            return new d(a, this, b)
        }
    }(),
    function(a) {
        a.hasFileAPI = function() {
            return void 0 !== window.FormData
        }, a.fn.cabinet = function(b) {
            b = a(b);
            var c = this,
                d = function(a, d, e, f) {
                    c.on(a, function(a) {
                        "click" === d ? b[0].click() : b.trigger(d), e && a.preventDefault(), f && f(a)
                    }, !1)
                };
            b[0].filelist = Object.create(FileList), b.on("change", function(a) {
                this.filelist = a.target.files, c.change()
            }), d("dragenter", "dragenter", !0), d("dragover", "dragover", !0), d("dragleave", "dragleave", !0), d("click", "click", !1), d("drop", "dragleave", !0, function(a) {
                b[0].filelist = a.dataTransfer.files, c.change()
            })
        }
    }($), $(function() {
		$('.jsonly').removeClass("d-none");
		$('.jsonly').prop('disabled', false);
		var randomizefn = ( $('#randomizefn').length > 0?($('#randomizefn').prop('checked')==false?0:1):1),
		 autodestroy = ( $('#autodestroy').length > 0?($('#autodestroy').prop('checked')==false?0:1):0),
		 shorturl = ( $('#shorturl').length > 0?($('#shorturl').prop('checked')==false?0:1):0), 
		 expire = ( $('#expsel').length > 0?($('#expsel').val()>=0?$('#expsel').val():60):60);
		
		$('#expsel').on('change', function(){ expire = $(this).val() });
		$('#autodestroy').on('change', function(){ autodestroy = $(this).prop('checked') == false ?  0 : 1 });
		$('#randomizefn').on('change', function(){ randomizefn = $(this).prop('checked') == false ?  0 : 1 });
		$('#shorturl').on('change', function(){ shorturl = $(this).prop('checked') == false ?  0 : 1 });
        var a = $("#upload-input"),
            b = $("#upload-btn"),
            c = $("#upload-filelist"),
            d = "";
        $.hasFileAPI() || ($("#no-file-api").show(), b.hide()), b.cabinet(a), b.on("dragenter", function(a) {
            this === a.target && ($(this).addClass("drop"), d = $(this).html(), $(this).html("Drop your file here"))
        }), b.on("drop", function(a) {
            $(this).trigger("dragleave")
        }), b.on("dragleave", function(a) {
            node = a.target;
            do
                if (node === this) {
                    $(this).removeClass("drop"), $(this).html(d);
                    break
                } while (node = node.parentNode)
        });
        var e = function(a) {
                var b = a.attr("data-max-size") || "100MiB",
                    c = parseInt(/([0-9,]+).*/.exec(b)[1].replace(",", "")),
                    d = /(?:([KMGTPEZY])(i)?B|([BKMGTPEZY]))/.exec(b) || ["B", "", ""],
                    e = Math.pow("i" === d[2] ? 1024 : 1e3, "BKMGTPEZY".indexOf(d[1]));
                return c * e
            }(a),
            f = function(a, b, c) {
                var d = $("<li class=file>"),
                    e = $("<span class=file-name>"),
                    f = $('<div class="file-progress progress-outer">'),
                    g = $("<span class=file-size>"),
                    h = $("<span class=file-url>");
                return d.addClass(c || ""), $("<div class=progress-inner>").appendTo(f), d.attr("data-filename", encodeURI(a)), e.text(a), g.text(b), d.append(e, f, g, h), d
            };
        b.on("change", function(b) {
            c.empty().removeClass("error completed");
            var d = a[0].filelist;
            d.forEach(function(a) {
                f(a.name, a.humanSize).appendTo(c)
            });
            var g = f("", d.humanSize, "total");
            if (g.appendTo(c), d.size > e) return c.addClass("error"), void $(".file-name", g).text("Your filesize exceeds the limit");
            var h = d.upload("/", {'expire':expire, 'autodestroy':autodestroy, 'randomizefn':randomizefn, 'shorturl':shorturl}),
                i = function(a, b) {
                    var c = {};
                    a.forEach(function(d) {
                        ++c[d.name] || (c[d.name] = 0);
                        var e = $($('li[data-filename="' + encodeURI(d.name) + '"]')[c[d.name] || 0]);
                        b.call(e, e, d, a)
                    })
                },
                j = $(".file-name", g);
            h.on("uploadprogress", function(a, b) {
                i(b, function(a, b, c) {
                    $(".progress-inner", a).width(100 * b.percentUploaded + "%")
                }), $(".progress-inner", g).width(100 * b.percentUploaded + "%")
            }), h.on("uploadcomplete", function(a) {
                $(".progress-inner").width("100%"), j.text("Grabbing URLs...")
            }), h.on("load", function(a, b) {
                switch (a.target.status) {
                    case 200:
                        var b = JSON.parse(b);
                        if (!b.success) {
                            c.addClass("error"), $(".file-name", g).text("Something went wrong; try again later.");
                            break
                        }
                        i(b.files, function(a, b, c) {

                            var d = $("<a>");
                            var m1 = $('<span> <a></a> </span>');
                            d.attr("href", b.url).attr("target", "_BLANK").text(b.url.replace("http://", "").replace("https://", "")), 
                            $(".file-url", a).append(d);
                            
                            m1.find('a').attr("href", b.manageurl).attr("target", "_BLANK").text('manage'),
                            $(".file-url", a).append(m1);
                            
                        }), c.addClass("completed"), j.text("Done!");
                        break;
                    case 413:
                        c.addClass("error completed"), j.html($("<div/>").html("Your filesize exceeds the limit").text());
                        break;
                    default:
                        c.addClass("error completed"), j.text("Something went wrong; try again later.")
                }
            }), h.upload()
        })
    });
