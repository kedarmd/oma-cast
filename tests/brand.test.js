const test = require('node:test')
const assert = require('node:assert/strict')
const Brand = require('../plugin/core/Brand.js')

test('kmDot logo themes the original strokes and accent dot independently', () => {
  for (const [primary, accent] of [['#a7c080', '#7fbbb3'], ['#88c0d0', '#81a1c1'], ['#7aa2f7', '#bb9af7']]) {
    const svg = decodeURIComponent(Brand.source(primary, accent).split(',')[1])
    assert.match(svg, new RegExp('stroke="' + primary + '"'))
    assert.match(svg, new RegExp('fill="' + accent + '"'))
    assert.equal(svg, Brand.SVG.replace('#c0caf5', primary).replace('fill="#7aa2f7"', 'fill="' + accent + '"'))
    assert.ok(!svg.includes('__PRIMARY__') && !svg.includes('__ACCENT__'))
  }
})

test('logo converts Qt ARGB paint to SVG RGB without altering geometry', () => {
  const svg = decodeURIComponent(Brand.source('#80a7c080', '#407fbbb3').split(',')[1])
  assert.ok(svg.includes('stroke="#a7c080"'))
  assert.ok(svg.includes('fill="#7fbbb3"'))
  assert.ok(svg.includes('viewBox="0 0 24 24"'))
})
