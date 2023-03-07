describe("Testing API Endpoints Using Cypress", () => {
  it("Test GET Request", () => {
    cy.request(
      "https://sz2l3yv8wi.execute-api.us-east-1.amazonaws.com/deployment/visitorsCount"
    ).then((response) => {
      expect(response.body).to.have.property("visitor");
    });
  });
});